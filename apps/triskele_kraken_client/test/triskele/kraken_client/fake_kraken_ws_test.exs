defmodule Triskele.KrakenClient.FakeKrakenWsTest do
  use ExUnit.Case, async: false

  alias Triskele.KrakenClient.FakeKrakenWs

  @moduletag :phase_1

  # ────────────────────────────────────────────────────────────────────────────
  # Harness self-tests — per DEV-009, a fake used by every downstream test
  # module deserves its own "does the fake itself work?" suite before the
  # downstream modules rely on it. The first test is the smallest possible
  # proof: TCP connect succeeds. Tests 3-5 exercise the full WS round-trip
  # via Mint.WebSocket so the validation is against the actual client library
  # used by production code.
  # ────────────────────────────────────────────────────────────────────────────

  describe "harness smoke test" do
    test "port/1 returns a positive integer for a running instance" do
      fake = start_supervised!(FakeKrakenWs)
      port = FakeKrakenWs.port(fake)

      assert is_integer(port)
      assert port > 0
    end

    test "TCP listener is reachable at the reported port" do
      fake = start_supervised!(FakeKrakenWs)
      port = FakeKrakenWs.port(fake)

      assert {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      :gen_tcp.close(socket)
    end
  end

  describe "multi-instance support" do
    test "two instances run concurrently on distinct ports" do
      fake_a = start_supervised!(FakeKrakenWs, id: :fake_a)
      fake_b = start_supervised!(FakeKrakenWs, id: :fake_b)

      port_a = FakeKrakenWs.port(fake_a)
      port_b = FakeKrakenWs.port(fake_b)

      # Each OS-assigned random port must be unique.
      refute port_a == port_b

      # Both listeners accept TCP connections independently.
      assert {:ok, sock_a} = :gen_tcp.connect(~c"127.0.0.1", port_a, [:binary, active: false])
      assert {:ok, sock_b} = :gen_tcp.connect(~c"127.0.0.1", port_b, [:binary, active: false])

      :gen_tcp.close(sock_a)
      :gen_tcp.close(sock_b)
    end
  end

  describe ":expect_token — private-channel token validation" do
    test "matching token receives success response" do
      fake = start_supervised!({FakeKrakenWs, [expect_token: "valid_token_abc"]})
      port = FakeKrakenWs.port(fake)

      {conn, websocket, ref} = ws_connect(port)

      frame =
        Jason.encode!(%{
          "method" => "subscribe",
          "params" => %{"channel" => "executions", "token" => "valid_token_abc"}
        })

      {:ok, {conn2, ws2}} = ws_send_text(conn, websocket, ref, frame)
      {:ok, response} = ws_recv_json(conn2, ws2, ref)

      assert response["success"] == true
      refute Map.has_key?(response, "error")
      assert response["method"] == "subscribe"
      assert get_in(response, ["result", "channel"]) == "executions"

      ws_close(conn2, ws2, ref)
    end

    test "wrong token receives error response" do
      fake = start_supervised!({FakeKrakenWs, [expect_token: "valid_token_abc"]})
      port = FakeKrakenWs.port(fake)

      {conn, websocket, ref} = ws_connect(port)

      frame =
        Jason.encode!(%{
          "method" => "subscribe",
          "params" => %{"channel" => "executions", "token" => "wrong_token_xyz"}
        })

      {:ok, {conn2, ws2}} = ws_send_text(conn, websocket, ref, frame)
      {:ok, response} = ws_recv_json(conn2, ws2, ref)

      assert response["success"] == false
      assert response["error"] == "ESession:Invalid session"
      assert response["method"] == "subscribe"

      ws_close(conn2, ws2, ref)
    end

    test "missing token receives error response" do
      fake = start_supervised!({FakeKrakenWs, [expect_token: "valid_token_abc"]})
      port = FakeKrakenWs.port(fake)

      {conn, websocket, ref} = ws_connect(port)

      # No "token" key in params — omitted entirely.
      frame =
        Jason.encode!(%{
          "method" => "subscribe",
          "params" => %{"channel" => "executions"}
        })

      {:ok, {conn2, ws2}} = ws_send_text(conn, websocket, ref, frame)
      {:ok, response} = ws_recv_json(conn2, ws2, ref)

      assert response["success"] == false
      assert response["error"] == "ESession:Invalid session"
      assert response["method"] == "subscribe"

      ws_close(conn2, ws2, ref)
    end
  end

  describe "backward compatibility — no :expect_token" do
    test "public-style subscribe without token receives per-symbol confirmation" do
      fake = start_supervised!(FakeKrakenWs)
      port = FakeKrakenWs.port(fake)

      {conn, websocket, ref} = ws_connect(port)

      frame =
        Jason.encode!(%{
          "method" => "subscribe",
          "params" => %{"channel" => "book", "symbol" => ["XBT/USD"]}
        })

      {:ok, {conn2, ws2}} = ws_send_text(conn, websocket, ref, frame)
      {:ok, response} = ws_recv_json(conn2, ws2, ref)

      assert response["success"] == true
      assert response["method"] == "subscribe"
      assert get_in(response, ["result", "channel"]) == "book"
      assert get_in(response, ["result", "symbol"]) == "XBT/USD"

      ws_close(conn2, ws2, ref)
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────
  # Duplicated rather than extracted to test/support per the deferred-helper-
  # extraction memo. Helper extraction is scheduled before Phase 2.

  # Performs a full Mint.WebSocket handshake against the fake and returns
  # `{conn, websocket, ref}` ready for frame send/receive.
  defp ws_connect(port) do
    uri = URI.parse("ws://127.0.0.1:#{port}/")
    {:ok, conn1} = Mint.HTTP.connect(:http, uri.host, uri.port, protocols: [:http1])
    {:ok, conn2, ref} = Mint.WebSocket.upgrade(:ws, conn1, uri.path || "/", [])
    {conn3, status, headers} = drain_upgrade(conn2)
    {:ok, conn4, websocket} = Mint.WebSocket.new(conn3, ref, status, headers)
    {conn4, websocket, ref}
  end

  # Drains Mint responses until the HTTP upgrade :done response is received.
  # Returns `{conn, status, headers}`.
  defp drain_upgrade(conn) do
    receive do
      msg ->
        {:ok, streamed_conn, responses} = Mint.WebSocket.stream(conn, msg)

        status =
          Enum.find_value(responses, fn
            {:status, _, s} -> s
            _ -> nil
          end)

        headers =
          Enum.find_value(responses, fn
            {:headers, _, h} -> h
            _ -> nil
          end)

        done? =
          Enum.any?(responses, fn
            {:done, _} -> true
            _ -> false
          end)

        if done? do
          {streamed_conn, status, headers}
        else
          # May need multiple rounds if responses arrive in fragments.
          {next_conn, status2, headers2} = drain_upgrade(streamed_conn)
          {next_conn, status || status2, headers || headers2}
        end
    after
      5_000 -> flunk("ws_connect: timed out waiting for upgrade response")
    end
  end

  # Sends a text frame over the WebSocket and returns `{:ok, {conn, websocket}}`.
  defp ws_send_text(conn, websocket, ref, text) do
    with {:ok, encoded_ws, data} <- Mint.WebSocket.encode(websocket, {:text, text}),
         {:ok, sent_conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      {:ok, {sent_conn, encoded_ws}}
    else
      {:error, _, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # Receives the next non-heartbeat text frame from the fake and returns
  # `{:ok, decoded_map}`. Skips heartbeat frames transparently.
  defp ws_recv_json(conn, websocket, ref) do
    receive do
      msg ->
        {:ok, streamed_conn, responses} = Mint.WebSocket.stream(conn, msg)
        handle_recv_responses(streamed_conn, websocket, ref, responses)
    after
      5_000 -> flunk("ws_recv_json: timed out waiting for response frame")
    end
  end

  defp handle_recv_responses(conn, websocket, ref, responses) do
    case find_data_payload(responses, ref) do
      {:ok, data} ->
        {:ok, decoded_ws, frames} = Mint.WebSocket.decode(websocket, data)
        handle_recv_frames(conn, decoded_ws, ref, frames)

      :none ->
        ws_recv_json(conn, websocket, ref)
    end
  end

  defp find_data_payload(responses, ref) do
    case Enum.find(responses, fn
           {:data, ^ref, _} -> true
           _ -> false
         end) do
      {:data, ^ref, data} -> {:ok, data}
      _ -> :none
    end
  end

  defp handle_recv_frames(conn, websocket, ref, frames) do
    case Enum.find(frames, fn
           {:text, _} -> true
           _ -> false
         end) do
      {:text, json} ->
        parsed = Jason.decode!(json)

        if parsed["channel"] == "heartbeat" do
          ws_recv_json(conn, websocket, ref)
        else
          {:ok, parsed}
        end

      nil ->
        ws_recv_json(conn, websocket, ref)
    end
  end

  defp ws_close(conn, websocket, ref) do
    case Mint.WebSocket.encode(websocket, :close) do
      {:ok, _ws, data} -> Mint.WebSocket.stream_request_body(conn, ref, data)
      _ -> :ok
    end

    Mint.HTTP.close(conn)
    :ok
  rescue
    _ -> :ok
  end
end
