defmodule Triskele.KrakenClient.FakeKrakenWs do
  @moduledoc """
  Minimal WebSocket server that mimics Kraken's v2 WebSocket API for tests.

  Starts a TCP listener on a random port. Each accepted connection performs
  the HTTP/1.1 WebSocket upgrade handshake, then enters a receive loop that
  handles application-level JSON messages per Kraken's v2 protocol.

  ## Kraken v2 ping/pong

  Kraken explicitly documents this as an *application-level* ping, distinct
  from WebSocket protocol-level frames (opcodes 0x9/0xA). The client sends:

      {"method": "ping", "req_id": 101}

  The server responds with:

      {"method": "pong", "req_id": 101, "success": true}

  This fake handles JSON pings and WebSocket protocol pings (opcode 0x9).

  ## Book snapshot checksum

  The `push_book_snapshot/5` API takes an explicit `checksum` parameter.
  Tests that exercise the happy path should pass the correct CRC32 value.
  Tests that exercise checksum-mismatch handling should pass a wrong value.
  The CRC32 algorithm over book levels is Phase 2's domain; this fake does
  not compute it automatically.

  ## Known limitation — single active connection

  This fake tracks one `conn_pid` at a time. The production WebSocket module
  manages two connections (public + private). Tests for private channels
  (`subscribe_own_trades/0`, `subscribe_open_orders/0`) will need a second
  fake instance started on a different port. That is deferred until the
  private WebSocket path is exercised in Phase 1 integration tests.
  """

  use GenServer

  import Bitwise

  @ws_guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  defstruct [:listen_socket, :port, :conn_pid, :conn_ref]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec port(pid()) :: non_neg_integer()
  def port(server), do: GenServer.call(server, :port)

  @spec push_frame(pid(), binary()) :: :ok
  def push_frame(server, json), do: GenServer.cast(server, {:push, json})

  @doc """
  Pushes a book snapshot to the connected client.

  `checksum` must be the correct CRC32 for the provided levels to avoid
  triggering a checksum-mismatch resubscription in the production client.
  Pass an intentionally wrong value to test that failure path.
  """
  @spec push_book_snapshot(pid(), String.t(), list(), list(), non_neg_integer()) :: :ok
  def push_book_snapshot(server, symbol, bids, asks, checksum) do
    frame =
      Jason.encode!(%{
        "channel" => "book",
        "type" => "snapshot",
        "data" => [
          %{
            "symbol" => symbol,
            "bids" => bids,
            "asks" => asks,
            "checksum" => checksum,
            "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
          }
        ]
      })

    push_frame(server, frame)
  end

  @doc """
  Kills the active connection, triggering a reconnect on the client side.
  After dropping, the server returns to accepting a new connection.
  """
  @spec drop_connection(pid()) :: :ok
  def drop_connection(server), do: GenServer.cast(server, :drop_connection)

  @spec stop(pid()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @impl GenServer
  def init(_opts) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(listen_socket)
    send(self(), :accept)
    {:ok, %__MODULE__{listen_socket: listen_socket, port: port, conn_pid: nil}}
  end

  @impl GenServer
  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  @impl GenServer
  def handle_cast({:push, json}, %{conn_pid: pid} = state) when is_pid(pid) do
    send(pid, {:push, json})
    {:noreply, state}
  end

  def handle_cast({:push, _}, state), do: {:noreply, state}

  def handle_cast(:drop_connection, %{conn_pid: pid} = state) when is_pid(pid) do
    Process.exit(pid, :kill)
    # :accept is re-armed by the {:DOWN, ...} message from the monitor
    {:noreply, state}
  end

  def handle_cast(:drop_connection, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.listen_socket, 2_000) do
      {:ok, socket} ->
        parent = self()

        # The accepted socket is owned by THIS GenServer. The child can't
        # take ownership itself (:gen_tcp.controlling_process/2 must be
        # called by the current owner). Spawn the child blocked on :owned,
        # transfer ownership, then unblock it — that ordering ensures the
        # child can safely call setopts(active: true) and receive the
        # subsequent {:tcp, ...} messages itself.
        pid =
          spawn(fn ->
            receive do
              :owned -> handle_connection(socket, parent)
            after
              5_000 -> :ok
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, :owned)

        ref = Process.monitor(pid)
        {:noreply, %{state | conn_pid: pid, conn_ref: ref}}

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    send(self(), :accept)
    {:noreply, %{state | conn_pid: nil, conn_ref: nil}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.conn_pid && Process.alive?(state.conn_pid) do
      Process.exit(state.conn_pid, :shutdown)
    end

    :gen_tcp.close(state.listen_socket)
  end

  defp handle_connection(socket, _parent) do
    case do_ws_handshake(socket) do
      :ok ->
        :inet.setopts(socket, active: true)
        ws_loop(socket)

      _error ->
        :ok
    end
  end

  defp do_ws_handshake(socket) do
    with {:ok, request} <- recv_http_request(socket),
         {:ok, key} <- parse_ws_key(request) do
      accept = compute_accept(key)

      response =
        "HTTP/1.1 101 Switching Protocols\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Accept: #{accept}\r\n\r\n"

      :gen_tcp.send(socket, response)
    end
  end

  defp recv_http_request(socket), do: recv_http_request(socket, "")

  defp recv_http_request(socket, acc) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        acc = acc <> data
        if String.contains?(acc, "\r\n\r\n"), do: {:ok, acc}, else: recv_http_request(socket, acc)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_ws_key(request) do
    case Regex.run(~r/Sec-WebSocket-Key: ([^\r\n]+)/i, request) do
      [_, key] -> {:ok, String.trim(key)}
      nil -> {:error, :no_ws_key}
    end
  end

  defp compute_accept(key) do
    Base.encode64(:crypto.hash(:sha, key <> @ws_guid))
  end

  defp ws_loop(socket) do
    receive do
      {:tcp, ^socket, data} ->
        handle_ws_data(socket, data)
        ws_loop(socket)

      {:tcp_closed, ^socket} ->
        :ok

      {:tcp_error, ^socket, _reason} ->
        :ok

      {:push, json} ->
        send_ws_text(socket, json)
        ws_loop(socket)
    after
      1_000 ->
        send_ws_text(socket, Jason.encode!(%{"channel" => "heartbeat"}))
        ws_loop(socket)
    end
  end

  defp handle_ws_data(socket, data) do
    case decode_ws_frame(data) do
      {:ok, :text, payload} -> handle_ws_message(socket, payload)
      {:ok, :ping, _} -> send_ws_pong(socket)
      {:ok, :close, _} -> :ok
      _ -> :ok
    end
  end

  defp handle_ws_message(socket, payload) do
    case Jason.decode(payload) do
      {:ok, %{"method" => "ping"} = msg} ->
        send_ws_text(
          socket,
          Jason.encode!(%{
            "method" => "pong",
            "req_id" => Map.get(msg, "req_id"),
            "time_in" => DateTime.to_iso8601(DateTime.utc_now()),
            "time_out" => DateTime.to_iso8601(DateTime.utc_now()),
            "success" => true
          })
        )

      {:ok, %{"method" => "subscribe", "params" => params}} ->
        send_subscribe_confirmation(socket, params["channel"], params["symbol"] || [])

      {:ok, %{"method" => "unsubscribe", "params" => params}} ->
        send_unsubscribe_confirmation(socket, params["channel"], params["symbol"] || [])

      _ ->
        :ok
    end
  end

  defp send_subscribe_confirmation(socket, channel, symbols) do
    for symbol <- symbols do
      send_ws_text(
        socket,
        Jason.encode!(%{
          "method" => "subscribe",
          "result" => %{"channel" => channel, "symbol" => symbol},
          "success" => true,
          "time_in" => DateTime.to_iso8601(DateTime.utc_now()),
          "time_out" => DateTime.to_iso8601(DateTime.utc_now())
        })
      )
    end
  end

  defp send_unsubscribe_confirmation(socket, channel, symbols) do
    for symbol <- symbols do
      send_ws_text(
        socket,
        Jason.encode!(%{
          "method" => "unsubscribe",
          "result" => %{"channel" => channel, "symbol" => symbol},
          "success" => true,
          "time_in" => DateTime.to_iso8601(DateTime.utc_now()),
          "time_out" => DateTime.to_iso8601(DateTime.utc_now())
        })
      )
    end
  end

  defp send_ws_text(socket, payload) do
    :gen_tcp.send(socket, encode_ws_frame(0x81, payload))
  end

  defp send_ws_pong(socket) do
    :gen_tcp.send(socket, encode_ws_frame(0x8A, ""))
  end

  defp encode_ws_frame(opcode_byte, payload) do
    len = byte_size(payload)

    length_bytes =
      cond do
        len <= 125 -> <<len::8>>
        len <= 65_535 -> <<126::8, len::16>>
        true -> <<127::8, len::64>>
      end

    <<opcode_byte::8>> <> length_bytes <> payload
  end

  defp decode_ws_frame(<<fin_opcode::8, rest::binary>>) do
    opcode = fin_opcode &&& 0x0F

    case rest do
      <<masked::1, len_byte::7, rest2::binary>> ->
        {payload_len, rest3} = parse_length(len_byte, rest2)
        {payload, _} = extract_payload(masked, payload_len, rest3)

        type =
          case opcode do
            0x1 -> :text
            0x2 -> :binary
            0x8 -> :close
            0x9 -> :ping
            0xA -> :pong
            _ -> :unknown
          end

        {:ok, type, payload}

      _ ->
        {:error, :incomplete}
    end
  end

  defp decode_ws_frame(_), do: {:error, :incomplete}

  defp parse_length(126, <<len::16, rest::binary>>), do: {len, rest}
  defp parse_length(127, <<len::64, rest::binary>>), do: {len, rest}
  defp parse_length(len, rest) when len <= 125, do: {len, rest}

  defp extract_payload(1, len, data) do
    <<mask::binary-size(4), payload::binary-size(len), rest::binary>> = data

    unmasked =
      payload
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.map(fn {byte, i} -> bxor(byte, :binary.at(mask, rem(i, 4))) end)
      |> :binary.list_to_bin()

    {unmasked, rest}
  end

  defp extract_payload(0, len, data) do
    <<payload::binary-size(len), rest::binary>> = data
    {payload, rest}
  end
end
