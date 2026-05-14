defmodule Triskele.KrakenClient.WebSocket.AuthTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Triskele.KrakenClient.HTTPClientMock
  alias Triskele.KrakenClient.Nonce
  alias Triskele.KrakenClient.RateLimit
  alias Triskele.KrakenClient.SecretKeeper
  alias Triskele.KrakenClient.WebSocket.Auth

  @moduletag :phase_1

  # Valid base64 test secret (decodes to "test_secret_base64_encoded").
  # Required because REST.private_post -> Signing.sign calls Base.decode64!.
  # Mirrors RESTTest's @test_secret.
  @test_secret "dGVzdF9zZWNyZXRfYmFzZTY0X2VuY29kZWQ="

  # ────────────────────────────────────────────────────────────────────────
  # Setup pattern mirrors RESTTest (Application.put_env + on_exit restore
  # for HTTPClientMock injection). Differs in one place: Mox runs in global
  # mode (set_mox_from_context + async: false) because Auth's REST call
  # happens inside the Auth GenServer process, and the refresh Task runs
  # in yet another process — private-mode Mox would not be visible there.
  # ────────────────────────────────────────────────────────────────────────
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    dets_path =
      Path.join(System.tmp_dir!(), "auth_test_nonce_#{System.unique_integer([:positive])}.dets")

    Application.put_env(:triskele_kraken_client, :nonce_dets_path, dets_path)
    Application.put_env(:triskele_kraken_client, :http_client, HTTPClientMock)
    Application.put_env(:triskele_kraken_client, :api_key, "test_key")
    Application.put_env(:triskele_kraken_client, :api_secret, @test_secret)

    start_supervised!({Nonce, []})
    start_supervised!({RateLimit, []})
    start_supervised!({SecretKeeper, []})

    on_exit(fn ->
      Application.delete_env(:triskele_kraken_client, :nonce_dets_path)
      Application.delete_env(:triskele_kraken_client, :http_client)
      Application.delete_env(:triskele_kraken_client, :api_key)
      Application.delete_env(:triskele_kraken_client, :api_secret)
      File.rm(dets_path)
    end)

    :ok
  end

  describe "start_link/1 test affordances" do
    test "starts under a custom :name option" do
      name = unique_name("Auth")

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"token" => "tok_start_link"})
      end)

      pid = start_supervised!({Auth, [name: name]})

      assert Process.whereis(name) == pid
      assert Process.alive?(pid)

      # Synchronize on handle_continue completion so Mox.verify_on_exit!
      # sees the count-bounded expect as consumed.
      wait_until(fn -> Auth.current_token(name) == "tok_start_link" end)
    end
  end

  describe "init/1" do
    test "successful REST.get_websocket_token boots with the returned token" do
      name = unique_name("Auth")

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"token" => "tok_init"})
      end)

      start_supervised!({Auth, [name: name]})

      assert Auth.current_token(name) == "tok_init"
    end

    test "REST failure during handle_continue causes Auth to terminate with the normalized error" do
      name = unique_name("Auth")

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      # init/1 returns immediately; handle_continue/2 runs the REST call
      # and on failure returns {:stop, reason, state}. The linked Auth
      # process exits with the normalized %Error{} struct as reason.
      # Trap exits so the EXIT signal doesn't take down the test.
      Process.flag(:trap_exit, true)
      {:ok, pid} = Auth.start_link(name: name)

      assert_receive {:EXIT, ^pid, err}, 5_000
      assert err.kind == :network_timeout
    end
  end

  describe "current_token/1" do
    test "reads the token from the running instance via the server arg" do
      name = unique_name("Auth")

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"token" => "tok_current"})
      end)

      start_supervised!({Auth, [name: name]})

      # Documents the /1 affordance specifically — the /0 form hardcoded
      # to __MODULE__ would not work here because the GenServer was
      # registered under `name`, not Auth.
      assert Auth.current_token(name) == "tok_current"
    end
  end

  describe "refresh cycle" do
    test "handle_info(:refresh_token) on success replaces the stored token" do
      name = unique_name("Auth")

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"token" => "tok_init"})
      end)

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"token" => "tok_refreshed"})
      end)

      start_supervised!({Auth, [name: name]})
      assert Auth.current_token(name) == "tok_init"

      # Drive the refresh directly via the message the production timer
      # would normally send. Wall-clock-independent: avoids waiting on
      # @refresh_after_ms (10 min) without requiring an interval-
      # injection affordance.
      send(name, :refresh_token)

      # State-based wait: current_token/1 is a sync GenServer.call, so
      # each poll drains Auth's mailbox before returning. Once the Task
      # has queued :refresh_result, the next poll processes it and the
      # state flips.
      wait_until(fn -> Auth.current_token(name) == "tok_refreshed" end)
    end

    test "handle_info(:refresh_token) on failure logs Logger.error and retains the previous token" do
      name = unique_name("Auth")
      test_pid = self()

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"token" => "tok_init"})
      end)

      stub(HTTPClientMock, :post, fn _url, _headers, _body ->
        # Signal that the refresh REST call has reached the mock. The
        # test uses this signal to bound the wait without depending on
        # wall-clock or peeking inside capture_log mid-flight.
        send(test_pid, :refresh_post_invoked)
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      start_supervised!({Auth, [name: name]})
      assert Auth.current_token(name) == "tok_init"

      log =
        capture_log(fn ->
          send(name, :refresh_token)
          assert_receive :refresh_post_invoked, 5_000

          # :sys.get_state/1 is a synchronous OTP system message
          # processed FIFO in the gen_server mailbox, so by the time
          # it returns, any messages queued ahead of it — including
          # the Task's subsequent `send(parent, {:refresh_result, ...})`
          # — have been processed and Logger.error has fired. Used
          # purely for sync (return value discarded); intent-clearer
          # than a state-observation GenServer.call.
          #
          # Residual race: between the stub's `send(test_pid, …)` and
          # the Task's subsequent send-to-Auth, the test process could
          # in principle call :sys.get_state before :refresh_result is
          # queued. The gap is the Task's REST error-normalization +
          # one send — microsecond-scale on any modern BEAM. Has not
          # manifested in practice. If this test goes flaky, switch
          # to a Logger-handler-based signal that fires AFTER the
          # warning is emitted.
          :sys.get_state(name)
        end)

      # Deferred telemetry-upgrade site per
      # project_deferred_telemetry_sites memo: when Phase 2 telemetry
      # lands, these capture_log assertions become
      # :telemetry_test.attach_event_handlers/2 assertions.
      assert log =~ "WebSocket.Auth token refresh failed:"
      assert log =~ "retaining current token"
      assert Auth.current_token(name) == "tok_init"
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # Helpers
  # ────────────────────────────────────────────────────────────────────────

  defp ok_response(result) do
    body = Jason.encode!(%{"error" => [], "result" => result})
    {:ok, 200, body}
  end

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
