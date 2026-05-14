defmodule Triskele.KrakenClient.WebSocket.PublicTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Triskele.KrakenClient.FakeKrakenWs
  alias Triskele.KrakenClient.WebSocket.Public
  alias Triskele.KrakenClient.WebSocket.SubscriptionRegistry

  @moduletag :phase_1

  # ────────────────────────────────────────────────────────────────────────
  # Per-test harness:
  #   - FakeKrakenWs on a random port → ws://127.0.0.1:<port>/
  #   - An isolated Phoenix.PubSub under a unique name
  # Each test then starts its own Public under a unique :name, pointed at
  # this fake + pubsub. start_supervised!/1 ties lifecycle to the test, so
  # cleanup is automatic on test exit.
  # ────────────────────────────────────────────────────────────────────────
  setup do
    fake = start_supervised!(FakeKrakenWs)
    port = FakeKrakenWs.port(fake)
    url = "ws://127.0.0.1:#{port}/"

    pubsub = unique_name("PubSub")
    start_supervised!({Phoenix.PubSub, name: pubsub})

    %{fake: fake, url: url, pubsub: pubsub}
  end

  describe "start_link/1 test affordances" do
    test "starts under a custom :name option", %{url: url, pubsub: pubsub} do
      name = unique_name("Public")

      pid = start_supervised!({Public, [name: name, url: url, pubsub: pubsub]})

      assert Process.whereis(name) == pid
      assert Process.alive?(pid)
    end

    test "init/1 uses the injected :registry value as starting state",
         %{url: url, pubsub: pubsub} do
      name = unique_name("Public")

      registry =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "XBT/USD")
        |> SubscriptionRegistry.add_desired("ticker", "ETH/USD")

      start_supervised!({Public, [name: name, url: url, pubsub: pubsub, registry: registry]})

      observed = Public.subscription_registry(name)

      assert SubscriptionRegistry.resubscribe_list(observed) ==
               %{"book" => ["XBT/USD"], "ticker" => ["ETH/USD"]}
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # Tests in this describe block bypass Public's subscribe_*/unsubscribe_*
  # public wrappers via direct GenServer.call/2. The wrappers hardcode
  # __MODULE__ (public.ex:107-131), which is incompatible with the per-test
  # :name isolation pattern the suite uses. The {:subscribe, channel,
  # symbols} / {:unsubscribe, channel, symbols} call shapes are stable
  # GenServer contract for these tests' purposes.
  # ────────────────────────────────────────────────────────────────────────
  describe "subscribe / unsubscribe round trip" do
    test "subscribe routes a ticker symbol through the wire and confirms it",
         %{url: url, pubsub: pubsub} do
      name = unique_name("Public")
      start_supervised!({Public, [name: name, url: url, pubsub: pubsub]})

      :ok = GenServer.call(name, {:subscribe, "ticker", ["ETH/USD"]})

      wait_until(fn ->
        reg = Public.subscription_registry(name)
        MapSet.member?(reg.confirmed, {"ticker", "ETH/USD"})
      end)

      reg = Public.subscription_registry(name)
      assert MapSet.member?(reg.desired, {"ticker", "ETH/USD"})
      assert MapSet.member?(reg.confirmed, {"ticker", "ETH/USD"})
    end

    test "unsubscribe removes the symbol from desired and confirmed",
         %{url: url, pubsub: pubsub} do
      name = unique_name("Public")

      registry =
        SubscriptionRegistry.add_desired(SubscriptionRegistry.new(), "book", "XBT/USD")

      start_supervised!({Public, [name: name, url: url, pubsub: pubsub, registry: registry]})

      wait_until(fn ->
        reg = Public.subscription_registry(name)
        MapSet.member?(reg.confirmed, {"book", "XBT/USD"})
      end)

      :ok = GenServer.call(name, {:unsubscribe, "book", ["XBT/USD"]})

      reg = Public.subscription_registry(name)
      refute MapSet.member?(reg.desired, {"book", "XBT/USD"})
      refute MapSet.member?(reg.confirmed, {"book", "XBT/USD"})
    end

    test "subscribe confirmation handler adds to confirmed regardless of desired state",
         %{fake: fake, url: url, pubsub: pubsub} do
      name = unique_name("Public")

      # Pre-seed ticker:ETH/USD as the wire-live signal: once the fake
      # auto-confirms it, the conn is up and push_frame/2 will reach the
      # client.
      registry =
        SubscriptionRegistry.add_desired(SubscriptionRegistry.new(), "ticker", "ETH/USD")

      start_supervised!({Public, [name: name, url: url, pubsub: pubsub, registry: registry]})

      wait_until(fn ->
        reg = Public.subscription_registry(name)
        MapSet.member?(reg.confirmed, {"ticker", "ETH/USD"})
      end)

      # book/XBT/USD is NOT in desired. Inject a success=true frame for it
      # directly; the handler must still mark it confirmed.
      injected =
        Jason.encode!(%{
          "method" => "subscribe",
          "result" => %{"channel" => "book", "symbol" => "XBT/USD"},
          "success" => true
        })

      FakeKrakenWs.push_frame(fake, injected)

      wait_until(fn ->
        reg = Public.subscription_registry(name)
        MapSet.member?(reg.confirmed, {"book", "XBT/USD"})
      end)

      reg = Public.subscription_registry(name)
      assert MapSet.member?(reg.confirmed, {"book", "XBT/USD"})
      refute MapSet.member?(reg.desired, {"book", "XBT/USD"})
    end

    test "failed subscribe confirmation marks rejected and logs a warning",
         %{fake: fake, url: url, pubsub: pubsub} do
      name = unique_name("Public")

      # Pre-seed BOTH symbols. The fake auto-confirms both, so
      # book:XBT/USD lands in confirmed; then the injected failure frame
      # for book:XBT/USD gives us a deterministic state-change signal
      # (book:XBT/USD leaving desired) to wait on. Without this seeding,
      # mark_rejected against a never-present key is a state no-op and
      # there is no synchronous signal that Public processed the frame.
      registry =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("ticker", "ETH/USD")
        |> SubscriptionRegistry.add_desired("book", "XBT/USD")

      start_supervised!({Public, [name: name, url: url, pubsub: pubsub, registry: registry]})

      wait_until(fn ->
        reg = Public.subscription_registry(name)
        MapSet.member?(reg.confirmed, {"book", "XBT/USD"})
      end)

      failure_frame =
        Jason.encode!(%{
          "method" => "subscribe",
          "result" => %{"channel" => "book", "symbol" => "XBT/USD"},
          "success" => false
        })

      log =
        capture_log(fn ->
          FakeKrakenWs.push_frame(fake, failure_frame)

          wait_until(fn ->
            reg = Public.subscription_registry(name)
            not MapSet.member?(reg.desired, {"book", "XBT/USD"})
          end)
        end)

      reg = Public.subscription_registry(name)
      refute MapSet.member?(reg.desired, {"book", "XBT/USD"})
      refute MapSet.member?(reg.confirmed, {"book", "XBT/USD"})

      assert log =~ "rejected"
      assert log =~ "channel=book"
      assert log =~ "symbol=XBT/USD"
    end

    test "subscribe issued while disconnected queues and fires on reconnect",
         %{fake: fake, url: url, pubsub: pubsub} do
      name = unique_name("Public")

      # First connect: pre-seed ticker:ETH/USD so we can detect the initial
      # connection landing (confirmed gains the symbol).
      registry =
        SubscriptionRegistry.add_desired(SubscriptionRegistry.new(), "ticker", "ETH/USD")

      start_supervised!({Public, [name: name, url: url, pubsub: pubsub, registry: registry]})

      wait_until(fn ->
        reg = Public.subscription_registry(name)
        MapSet.member?(reg.confirmed, {"ticker", "ETH/USD"})
      end)

      # Drop the fake's connection. Public's stream loop sees the abrupt
      # close and fires trigger_reconnect: status -> :disconnected,
      # confirmed cleared, reconnect scheduled @reconnect_delay_ms (3_000)
      # out.
      FakeKrakenWs.drop_connection(fake)

      # Issue a new subscribe while disconnected. handle_call adds to
      # desired but does NOT send (status != :connected). The subscription
      # must ride out on the reconnect via resubscribe_all.
      :ok = GenServer.call(name, {:subscribe, "book", ["XBT/USD"]})

      # 7 s timeout covers @reconnect_delay_ms (3 s) + TCP/upgrade +
      # fake auto-confirm with margin.
      wait_until(
        fn ->
          reg = Public.subscription_registry(name)
          MapSet.member?(reg.confirmed, {"book", "XBT/USD"})
        end,
        7_000
      )
    end
  end

  describe "handle_response/2 — pre-upgrade :data guard" do
    test "drops :data frame when websocket struct is not yet constructed",
         %{url: url, pubsub: pubsub} do
      name = unique_name("Public")

      start_supervised!({Public, [name: name, url: url, pubsub: pubsub]})

      # Wait for the connection to reach :connected (so state.conn has the
      # post-upgrade :websockets private set by Mint.WebSocket.new/5).
      # Subsequent inbound TCP messages will reach Mint.WebSocket.stream/2's
      # stream_http1 branch (mint_web_socket lib/mint/web_socket.ex:416),
      # which wraps raw TCP data as `{:data, ref, bytes}` responses — exactly
      # the response shape that triggers handle_response({:data, ...}, ...).
      wait_until(fn ->
        state = :sys.get_state(name)
        state.status == :connected
      end)

      # Forcibly reset websocket: nil + status: :connecting on a running
      # GenServer to reproduce the pre-upgrade state that Kraken triggers
      # in production by pipelining a server frame with the 101 Switching
      # Protocols response. FakeKrakenWs separates handshake from frames
      # by ≥1 s (its receive/after window), so the condition never arises
      # naturally in the test harness.
      :sys.replace_state(name, fn s ->
        %{s | websocket: nil, status: :connecting}
      end)

      # FakeKrakenWs sends a heartbeat every 1 s of socket idle. Capture
      # log around that window to observe the pre-upgrade :data drop.
      log =
        capture_log(fn ->
          Process.sleep(1_500)
        end)

      assert log =~ "WebSocket.Public dropping pre-upgrade :data frame"
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # Helpers
  # ────────────────────────────────────────────────────────────────────────

  defp wait_until(fun, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline, timeout)
  end

  defp do_wait_until(fun, deadline, timeout) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("wait_until timed out after #{timeout}ms")

      true ->
        Process.sleep(20)
        do_wait_until(fun, deadline, timeout)
    end
  end

  defp unique_name(prefix) do
    # Test-only helper. Atom-table growth is bounded by the number of
    # test invocations in a single suite run, with one atom per call.
    # Credo's UnsafeToAtom targets unbounded atom creation from
    # external input (HTTP params, user data, etc.) — not bounded
    # creation in test scope.
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    :"#{prefix}_#{:erlang.unique_integer([:positive])}"
  end
end
