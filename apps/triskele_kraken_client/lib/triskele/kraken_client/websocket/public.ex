defmodule Triskele.KrakenClient.WebSocket.Public do
  @moduledoc """
  GenServer that maintains a persistent public WebSocket connection to Kraken v2.

  Subscribes to `book` (order-book snapshots + deltas) and `ticker` channels.
  Publishes decoded events to Phoenix.PubSub:

  - `"book:<sym>:snapshot"` — `{:book_snapshot, %OrderBook{}, received_at_ms}`
  - `"book:<sym>:update"`   — `{:book_update, %BookUpdate{}, received_at_ms}`
  - `"book:<sym>:reset"`    — `{:book_reset, symbol}` — CRC mismatch; wait for snapshot
  - `"ticker:<sym>"`        — `{:ticker, %Ticker{}, received_at_ms}`

  Desired subscriptions survive reconnects. On disconnect the confirmed set is
  cleared; resubscriptions are batched and sent once the new connection is up.

  ## Liveness

  Application-level pings are sent every `@ping_interval_ms`. A pong timeout
  timer is armed when the ping is sent; if no matching pong arrives within
  `@pong_timeout_ms`, the connection is treated as dead and a reconnect is
  triggered. This catches half-open connections that TCP keepalive may not
  detect quickly enough.

  A staleness watchdog runs every `@staleness_check_ms` and logs a warning for
  any subscribed symbol that has been silent for more than `@staleness_threshold_ms`.

  ## Config

  All `start_link/1` opts are optional and default to production values:

  - `:url` — WebSocket endpoint. Defaults to
    `Application.get_env(:triskele_kraken_client, :public_ws_url,
    "wss://ws.kraken.com/v2")`.
  - `:pubsub` — `Phoenix.PubSub` server name to broadcast on. Defaults to
    `Triskele.PubSub`.
  - `:name` — GenServer registered name. Defaults to `__MODULE__`. Tests
    that need isolated instances pass a unique atom so each one registers
    under its own name.
  - `:registry` — initial `SubscriptionRegistry` value. Defaults to
    `SubscriptionRegistry.new()`. Tests can inject a pre-populated registry
    to set up scenarios without going through the subscribe/confirm
    round-trip.
  """

  use GenServer

  require Logger

  alias Triskele.KrakenClient.Types.Ticker
  alias Triskele.KrakenClient.WebSocket.BookMaintenance
  alias Triskele.KrakenClient.WebSocket.Connection
  alias Triskele.KrakenClient.WebSocket.SubscriptionRegistry
  alias Triskele.KrakenClient.WebSocket.Wire

  @ping_interval_ms 30_000
  @pong_timeout_ms 10_000
  @reconnect_delay_ms 3_000
  @staleness_check_ms 15_000
  @staleness_threshold_ms 30_000
  @book_depth 10

  @enforce_keys [:url, :pubsub, :sub_reg]
  defstruct [
    :conn,
    :websocket,
    :ref,
    :ping_timer,
    :pong_timer,
    :outstanding_ping_id,
    :upgrade_status,
    :upgrade_headers,
    :url,
    :pubsub,
    sub_reg: nil,
    local_book: %{},
    last_message_at: %{},
    status: :disconnected
  ]

  @type t :: %__MODULE__{
          conn: Mint.HTTP.t() | nil,
          websocket: Mint.WebSocket.t() | nil,
          ref: Mint.Types.request_ref() | nil,
          ping_timer: reference() | nil,
          pong_timer: reference() | nil,
          outstanding_ping_id: integer() | nil,
          upgrade_status: non_neg_integer() | nil,
          upgrade_headers: [{String.t(), String.t()}] | nil,
          url: String.t(),
          pubsub: atom(),
          sub_reg: SubscriptionRegistry.t(),
          local_book: %{String.t() => BookMaintenance.book()},
          last_message_at: %{String.t() => integer()},
          status: :disconnected | :connecting | :connected
        }

  # ── Public API ─────────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec subscribe_book(String.t() | [String.t(), ...]) :: :ok
  def subscribe_book([_ | _] = symbols) do
    GenServer.call(__MODULE__, {:subscribe, "book", symbols})
  end

  def subscribe_book(symbol) when is_binary(symbol), do: subscribe_book([symbol])

  @spec subscribe_ticker(String.t() | [String.t(), ...]) :: :ok
  def subscribe_ticker([_ | _] = symbols) do
    GenServer.call(__MODULE__, {:subscribe, "ticker", symbols})
  end

  def subscribe_ticker(symbol) when is_binary(symbol), do: subscribe_ticker([symbol])

  @spec unsubscribe_book(String.t() | [String.t(), ...]) :: :ok
  def unsubscribe_book([_ | _] = symbols) do
    GenServer.call(__MODULE__, {:unsubscribe, "book", symbols})
  end

  def unsubscribe_book(symbol) when is_binary(symbol), do: unsubscribe_book([symbol])

  @spec unsubscribe_ticker(String.t() | [String.t(), ...]) :: :ok
  def unsubscribe_ticker([_ | _] = symbols) do
    GenServer.call(__MODULE__, {:unsubscribe, "ticker", symbols})
  end

  def unsubscribe_ticker(symbol) when is_binary(symbol), do: unsubscribe_ticker([symbol])

  @spec subscription_registry(GenServer.server()) :: SubscriptionRegistry.t()
  def subscription_registry(server \\ __MODULE__) do
    GenServer.call(server, :subscription_registry)
  end

  # ── GenServer callbacks ────────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    url = Keyword.get(opts, :url, default_ws_url())
    pubsub = Keyword.get(opts, :pubsub, Triskele.PubSub)
    sub_reg = Keyword.get_lazy(opts, :registry, &SubscriptionRegistry.new/0)
    send(self(), :connect)
    Process.send_after(self(), :check_staleness, @staleness_check_ms)

    {:ok,
     %__MODULE__{
       url: url,
       pubsub: pubsub,
       sub_reg: sub_reg,
       local_book: %{},
       last_message_at: %{}
     }}
  end

  @impl GenServer
  def handle_call({:subscribe, channel, symbols}, _from, state) do
    updated =
      Enum.reduce(symbols, state, fn sym, acc ->
        %{acc | sub_reg: SubscriptionRegistry.add_desired(acc.sub_reg, channel, sym)}
      end)

    new_state =
      if updated.status == :connected,
        do: send_subscribe(updated, channel, symbols),
        else: updated

    {:reply, :ok, new_state}
  end

  def handle_call({:unsubscribe, channel, symbols}, _from, state) do
    updated =
      Enum.reduce(symbols, state, fn sym, acc ->
        %{acc | sub_reg: SubscriptionRegistry.remove_desired(acc.sub_reg, channel, sym)}
      end)

    new_state =
      if updated.status == :connected,
        do: send_unsubscribe(updated, channel, symbols),
        else: updated

    {:reply, :ok, new_state}
  end

  def handle_call(:subscription_registry, _from, state) do
    {:reply, state.sub_reg, state}
  end

  @impl GenServer
  def handle_info(:connect, state) do
    case Connection.connect(state.url) do
      {:ok, {conn, ref}} ->
        {:noreply,
         %{
           state
           | conn: conn,
             ref: ref,
             status: :connecting,
             upgrade_status: nil,
             upgrade_headers: nil
         }}

      {:error, reason} ->
        Logger.warning("WebSocket.Public connect failed: #{inspect(reason)}, retrying")
        Process.send_after(self(), :connect, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  def handle_info(:send_ping, state) do
    req_id = System.unique_integer([:positive])

    case Connection.send_text(state.conn, state.websocket, state.ref, Wire.ping_payload(req_id)) do
      {:ok, {conn, ws}} ->
        if state.pong_timer, do: Process.cancel_timer(state.pong_timer)
        pong_timer = Process.send_after(self(), {:pong_timeout, req_id}, @pong_timeout_ms)

        {:noreply,
         %{
           state
           | conn: conn,
             websocket: ws,
             ping_timer: nil,
             pong_timer: pong_timer,
             outstanding_ping_id: req_id
         }}

      {:error, _} ->
        {:noreply, trigger_reconnect(state)}
    end
  end

  def handle_info({:pong_timeout, ping_id}, %{outstanding_ping_id: ping_id} = state) do
    Logger.warning("WebSocket.Public pong timeout ping_id=#{ping_id}, reconnecting")
    {:noreply, trigger_reconnect(state)}
  end

  def handle_info({:pong_timeout, _stale_id}, state), do: {:noreply, state}

  def handle_info(:check_staleness, state) do
    if state.status == :connected do
      now = System.monotonic_time(:millisecond)

      Enum.each(state.last_message_at, fn {symbol, last_at} ->
        silent_ms = now - last_at

        if silent_ms > @staleness_threshold_ms do
          # TODO Phase 2: replace with :telemetry.execute/3 once telemetry hub exists
          Logger.warning(
            "WebSocket.Public stale subscription symbol=#{symbol} silent_ms=#{silent_ms}"
          )
        end
      end)
    end

    Process.send_after(self(), :check_staleness, @staleness_check_ms)
    {:noreply, state}
  end

  def handle_info(msg, %{conn: conn} = state) when conn != nil do
    case Connection.stream(conn, msg) do
      {:ok, new_conn, responses} ->
        state = Enum.reduce(responses, %{state | conn: new_conn}, &handle_response/2)
        {:noreply, state}

      {:error, new_conn, _reason, responses} ->
        state = Enum.reduce(responses, %{state | conn: new_conn}, &handle_response/2)
        {:noreply, trigger_reconnect(state)}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Mint response handling ─────────────────────────────────────────────────

  defp handle_response({:status, _ref, status}, state) do
    %{state | upgrade_status: status}
  end

  defp handle_response({:headers, _ref, headers}, state) do
    %{state | upgrade_headers: headers}
  end

  defp handle_response({:done, _ref}, state) do
    case Connection.finalize_upgrade(
           state.conn,
           state.ref,
           state.upgrade_status,
           state.upgrade_headers
         ) do
      {:ok, {conn, websocket}} ->
        state = %{state | conn: conn, websocket: websocket, status: :connected}
        state = schedule_ping(state)
        resubscribe_all(state)

      {:error, reason} ->
        Logger.error("WebSocket.Public upgrade failed: #{inspect(reason)}")
        trigger_reconnect(state)
    end
  end

  defp handle_response({:data, _ref, data}, state) do
    case Connection.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        Enum.reduce(frames, %{state | websocket: websocket}, &handle_frame/2)

      {:error, websocket, _reason} ->
        trigger_reconnect(%{state | websocket: websocket})
    end
  end

  defp handle_response(_response, state), do: state

  # ── WebSocket frame handling ───────────────────────────────────────────────

  defp handle_frame({:text, json}, state) do
    case Jason.decode(json) do
      {:ok, msg} -> dispatch_message(msg, state)
      {:error, _} -> state
    end
  end

  defp handle_frame({:ping, payload}, state) do
    case Connection.send_frame(state.conn, state.websocket, state.ref, {:pong, payload}) do
      {:ok, {conn, ws}} -> %{state | conn: conn, websocket: ws}
      {:error, _} -> trigger_reconnect(state)
    end
  end

  defp handle_frame({:close, _, _}, state), do: trigger_reconnect(state)
  defp handle_frame(_frame, state), do: state

  # ── Message dispatch ───────────────────────────────────────────────────────

  defp dispatch_message(%{"channel" => "book", "type" => "snapshot", "data" => data_list}, state) do
    Enum.reduce(data_list, state, &handle_book_snapshot/2)
  end

  defp dispatch_message(%{"channel" => "book", "type" => "update", "data" => data_list}, state) do
    Enum.reduce(data_list, state, &handle_book_update/2)
  end

  defp dispatch_message(
         %{"channel" => "ticker", "type" => "update", "data" => data_list},
         state
       ) do
    received_at = System.monotonic_time(:millisecond)

    Enum.reduce(data_list, state, fn data, acc ->
      ticker = Ticker.from_ws(data)

      Phoenix.PubSub.broadcast(
        acc.pubsub,
        "ticker:#{ticker.symbol}",
        {:ticker, ticker, received_at}
      )

      put_last_message_at(acc, ticker.symbol)
    end)
  end

  defp dispatch_message(
         %{"method" => "pong", "req_id" => req_id},
         %{outstanding_ping_id: req_id} = state
       ) do
    if state.pong_timer, do: Process.cancel_timer(state.pong_timer)
    schedule_ping(%{state | pong_timer: nil, outstanding_ping_id: nil})
  end

  defp dispatch_message(%{"method" => "pong"}, state), do: state

  defp dispatch_message(
         %{"method" => "subscribe", "result" => result, "success" => true},
         state
       ) do
    %{
      state
      | sub_reg:
          SubscriptionRegistry.mark_confirmed(state.sub_reg, result["channel"], result["symbol"])
    }
  end

  defp dispatch_message(
         %{"method" => "subscribe", "result" => result, "success" => false},
         state
       ) do
    channel = result["channel"]
    symbol = result["symbol"]
    Logger.warning("WebSocket.Public subscribe rejected channel=#{channel} symbol=#{symbol}")
    %{state | sub_reg: SubscriptionRegistry.mark_rejected(state.sub_reg, channel, symbol)}
  end

  defp dispatch_message(%{"channel" => "heartbeat"}, state), do: state
  defp dispatch_message(_msg, state), do: state

  # ── Book snapshot ──────────────────────────────────────────────────────────

  defp handle_book_snapshot(data, state) do
    symbol = data["symbol"]
    received_at = System.monotonic_time(:millisecond)

    case BookMaintenance.init_from_snapshot(data) do
      {:ok, book, order_book} ->
        Phoenix.PubSub.broadcast(
          state.pubsub,
          "book:#{symbol}:snapshot",
          {:book_snapshot, order_book, received_at}
        )

        state
        |> Map.put(:local_book, Map.put(state.local_book, symbol, book))
        |> put_last_message_at(symbol)

      {:error, :checksum_mismatch} ->
        Logger.warning("WebSocket.Public snapshot CRC mismatch symbol=#{symbol}")
        handle_book_reset(symbol, state)
    end
  end

  # ── Book update ────────────────────────────────────────────────────────────

  defp handle_book_update(data, state) do
    symbol = data["symbol"]
    received_at = System.monotonic_time(:millisecond)

    case Map.fetch(state.local_book, symbol) do
      {:ok, book} ->
        case BookMaintenance.apply_update(book, data) do
          {:ok, updated_book, book_update} ->
            Phoenix.PubSub.broadcast(
              state.pubsub,
              "book:#{symbol}:update",
              {:book_update, book_update, received_at}
            )

            state
            |> Map.put(:local_book, Map.put(state.local_book, symbol, updated_book))
            |> put_last_message_at(symbol)

          {:error, :checksum_mismatch} ->
            Logger.warning("WebSocket.Public update CRC mismatch symbol=#{symbol}")
            handle_book_reset(symbol, state)
        end

      :error ->
        state
    end
  end

  # ── Book reset ─────────────────────────────────────────────────────────────

  defp handle_book_reset(symbol, state) do
    Phoenix.PubSub.broadcast(state.pubsub, "book:#{symbol}:reset", {:book_reset, symbol})

    state = %{
      state
      | local_book: Map.delete(state.local_book, symbol),
        sub_reg: SubscriptionRegistry.unconfirm(state.sub_reg, "book", symbol)
    }

    send_subscribe(state, "book", [symbol])
  end

  # ── Reconnection ───────────────────────────────────────────────────────────

  defp trigger_reconnect(state) do
    if state.conn, do: Connection.close(state.conn, state.websocket, state.ref)
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    if state.pong_timer, do: Process.cancel_timer(state.pong_timer)
    Process.send_after(self(), :connect, @reconnect_delay_ms)

    %{
      state
      | conn: nil,
        websocket: nil,
        ref: nil,
        ping_timer: nil,
        pong_timer: nil,
        outstanding_ping_id: nil,
        upgrade_status: nil,
        upgrade_headers: nil,
        local_book: %{},
        last_message_at: %{},
        sub_reg: SubscriptionRegistry.clear_confirmed(state.sub_reg),
        status: :disconnected
    }
  end

  defp resubscribe_all(state) do
    state.sub_reg
    |> SubscriptionRegistry.resubscribe_list()
    |> Enum.reduce(state, fn {channel, symbols}, acc ->
      send_subscribe(acc, channel, symbols)
    end)
  end

  # ── Wire protocol helpers ──────────────────────────────────────────────────

  defp send_subscribe(state, "book", symbols) do
    send_text_or_reconnect(state, Wire.subscribe_book_payload(symbols, @book_depth))
  end

  defp send_subscribe(state, "ticker", symbols) do
    send_text_or_reconnect(state, Wire.subscribe_ticker_payload(symbols))
  end

  defp send_unsubscribe(state, channel, symbols) do
    send_text_or_reconnect(state, Wire.unsubscribe_payload(channel, symbols))
  end

  defp send_text_or_reconnect(state, payload) do
    case Connection.send_text(state.conn, state.websocket, state.ref, payload) do
      {:ok, {conn, ws}} -> %{state | conn: conn, websocket: ws}
      {:error, _} -> trigger_reconnect(state)
    end
  end

  # ── State helpers ──────────────────────────────────────────────────────────

  defp schedule_ping(state) do
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    timer = Process.send_after(self(), :send_ping, @ping_interval_ms)
    %{state | ping_timer: timer}
  end

  defp put_last_message_at(state, symbol) do
    %{
      state
      | last_message_at:
          Map.put(state.last_message_at, symbol, System.monotonic_time(:millisecond))
    }
  end

  defp default_ws_url do
    Application.get_env(:triskele_kraken_client, :public_ws_url, "wss://ws.kraken.com/v2")
  end
end
