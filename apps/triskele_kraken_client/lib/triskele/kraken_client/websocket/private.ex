defmodule Triskele.KrakenClient.WebSocket.Private do
  @moduledoc """
  GenServer that maintains a persistent authenticated WebSocket connection to
  Kraken's private v2 endpoint (`wss://ws-auth.kraken.com/v2`).

  Subscribes to the `executions` channel (Kraken v2 unified channel for order
  fills and state changes, replacing v1's `ownTrades` + `openOrders`).
  Publishes decoded events to Phoenix.PubSub:

  - `"executions"` — `{:executions, %{type: :snapshot | :update, data: [...], sequence: N}}`

  ## Token isolation

  The WebSocket authentication token is read from `WebSocket.Auth.current_token/1`
  at subscribe time only (initial subscribe and reconnect resubscribe). It is NOT
  held in Private's state. This provides isolation: a `:sys.get_state/1` call or
  crash dump reveals no token value.

  ## Mid-refresh race recovery

  When a subscribe attempt receives `"ESession:Invalid session"`, Private:
  1. Sleeps 100ms to allow Auth's in-flight refresh Task to complete.
  2. Re-reads `Auth.current_token/1` with the injected `:auth` server name.
  3. Retries the subscribe ONCE with the same opts.
  4. On a second `"ESession:Invalid session"` → triggers a reconnect.

  The 100ms sleep is intentional per the auth-refresh-race-telemetry memo.
  Without it the retry happens in microseconds and is likely to read the same
  stale token. See `~/.claude/projects/.../memory/project_auth_refresh_race_telemetry.md`.

  ## Reconnect strategy (DEV-010 §4)

  Tiered reconnect per Kraken v2 guidance:
  - First attempt: instant (via `send/2` with no delay).
  - Subsequent attempts: `@reconnect_backoff_ms` (default 5_000 ms).
  An attempt counter is held in state and reset to 0 on successful connect
  (when the HTTP upgrade `:done` lands and `status` becomes `:connected`).

  ## Sequence numbers

  Executions frames include a `"sequence"` field that is broadcast as-is.
  Sequence-number gap detection and recovery are OUT OF SCOPE for Phase 1.

  # TODO Phase 2: implement sequence-number gap detection. On gap (sequence N
  # received after sequence M where N > M + 1), trigger a reconnect to force
  # a fresh snapshot from Kraken.

  ## Config

  All `start_link/1` opts are optional and default to production values:

  - `:url` — WebSocket endpoint. Defaults to
    `Application.get_env(:triskele_kraken_client, :private_ws_url,
    "wss://ws-auth.kraken.com/v2")`.
  - `:pubsub` — `Phoenix.PubSub` server name to broadcast on. Defaults to
    `Triskele.PubSub`.
  - `:auth` — Auth server name/pid. Defaults to
    `Triskele.KrakenClient.WebSocket.Auth`. Tests inject a mock.
  - `:name` — GenServer registered name. Defaults to `__MODULE__`. Tests
    pass a unique atom for isolation.
  - `:ping_interval_ms` — Override ping interval. Defaults to
    `@ping_interval_ms` (30_000). Tests pass a short value (e.g., 100).
  - `:reconnect_backoff_ms` — Override backoff for subsequent reconnect
    attempts. Defaults to `@reconnect_backoff_ms` (5_000). Tests pass a
    short value (e.g., 200) to avoid slow-test penalties.
  """

  use GenServer

  require Logger

  alias Triskele.KrakenClient.WebSocket.Auth
  alias Triskele.KrakenClient.WebSocket.Connection
  alias Triskele.KrakenClient.WebSocket.SubscriptionRegistry
  alias Triskele.KrakenClient.WebSocket.Wire

  @ping_interval_ms 30_000
  @pong_timeout_ms 10_000
  @reconnect_backoff_ms 5_000

  @enforce_keys [:url, :pubsub, :auth, :sub_reg, :ping_interval_ms, :reconnect_backoff_ms]
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
    :auth,
    :ping_interval_ms,
    :reconnect_backoff_ms,
    sub_reg: nil,
    subscribe_opts: [],
    status: :disconnected,
    reconnect_attempts: 0
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
          auth: atom() | pid(),
          ping_interval_ms: pos_integer(),
          reconnect_backoff_ms: pos_integer(),
          sub_reg: SubscriptionRegistry.t(),
          subscribe_opts: keyword(),
          status: :disconnected | :connecting | :connected,
          reconnect_attempts: non_neg_integer()
        }

  # ── Public API ─────────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec subscribe_executions() :: :ok
  def subscribe_executions do
    GenServer.call(__MODULE__, {:subscribe_executions, []})
  end

  @spec subscribe_executions(keyword()) :: :ok
  def subscribe_executions(opts) do
    GenServer.call(__MODULE__, {:subscribe_executions, opts})
  end

  @spec unsubscribe_executions() :: :ok
  def unsubscribe_executions do
    GenServer.call(__MODULE__, :unsubscribe_executions)
  end

  @spec subscription_registry(GenServer.server()) :: SubscriptionRegistry.t()
  def subscription_registry(server \\ __MODULE__) do
    GenServer.call(server, :subscription_registry)
  end

  # ── GenServer callbacks ────────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    url = Keyword.get(opts, :url, default_ws_url())
    pubsub = Keyword.get(opts, :pubsub, Triskele.PubSub)
    auth = Keyword.get(opts, :auth, Auth)
    ping_ms = Keyword.get(opts, :ping_interval_ms, @ping_interval_ms)
    reconnect_ms = Keyword.get(opts, :reconnect_backoff_ms, @reconnect_backoff_ms)

    send(self(), :connect)

    {:ok,
     %__MODULE__{
       url: url,
       pubsub: pubsub,
       auth: auth,
       ping_interval_ms: ping_ms,
       reconnect_backoff_ms: reconnect_ms,
       sub_reg: SubscriptionRegistry.new(),
       subscribe_opts: []
     }}
  end

  @impl GenServer
  def handle_call({:subscribe_executions, opts}, _from, state) do
    updated_opts = if opts == [], do: state.subscribe_opts, else: opts

    with_opts = %{state | subscribe_opts: updated_opts}

    with_desired = %{
      with_opts
      | sub_reg: SubscriptionRegistry.add_desired(with_opts.sub_reg, "executions", nil)
    }

    result_state =
      if with_desired.status == :connected do
        do_subscribe_executions(with_desired, updated_opts)
      else
        with_desired
      end

    {:reply, :ok, result_state}
  end

  def handle_call(:unsubscribe_executions, _from, state) do
    updated_reg = SubscriptionRegistry.remove_desired(state.sub_reg, "executions", nil)
    new_state = %{state | sub_reg: updated_reg, subscribe_opts: []}

    result_state =
      if new_state.status == :connected do
        send_unsubscribe_executions(new_state)
      else
        new_state
      end

    {:reply, :ok, result_state}
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
        Logger.warning("WebSocket.Private connect failed: #{inspect(reason)}, retrying")
        new_state = schedule_reconnect(state)
        {:noreply, new_state}
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
    Logger.warning("WebSocket.Private pong timeout ping_id=#{ping_id}, reconnecting")
    {:noreply, trigger_reconnect(state)}
  end

  def handle_info({:pong_timeout, _stale_id}, state), do: {:noreply, state}

  def handle_info(msg, %{conn: conn} = state) when conn != nil do
    case Connection.stream(conn, msg) do
      {:ok, new_conn, responses} ->
        new_state = Enum.reduce(responses, %{state | conn: new_conn}, &handle_response/2)
        {:noreply, new_state}

      {:error, new_conn, _reason, responses} ->
        new_state = Enum.reduce(responses, %{state | conn: new_conn}, &handle_response/2)
        {:noreply, trigger_reconnect(new_state)}

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
        connected_state = %{
          state
          | conn: conn,
            websocket: websocket,
            status: :connected,
            reconnect_attempts: 0
        }

        connected_state = schedule_ping(connected_state)
        resubscribe_on_reconnect(connected_state)

      {:error, reason} ->
        Logger.error("WebSocket.Private upgrade failed: #{inspect(reason)}")
        trigger_reconnect(state)
    end
  end

  defp handle_response({:data, _ref, data}, %{websocket: nil} = state) do
    # WebSocket frame data arrived during HTTP upgrade phase: Kraken
    # pipelined a server frame with the 101 Switching Protocols
    # response such that Mint emitted :data without a preceding
    # :done in the same stream batch. state.websocket has not yet
    # been constructed via Mint.WebSocket.new/5 (that happens in
    # the :done handler below).
    #
    # We log the dropped frame at :warning with byte length and a
    # short hex preview for forensic visibility. Phase 2 should
    # decide whether to buffer these bytes and re-decode after
    # upgrade completes, vs. continuing to drop them (Kraken
    # appears to re-send any caller-observable state at
    # subscribe-confirmation time, so dropping may remain safe).
    preview =
      data
      |> binary_part(0, min(byte_size(data), 32))
      |> Base.encode16()

    Logger.warning(
      "WebSocket.Private dropping pre-upgrade :data frame " <>
        "(#{byte_size(data)} bytes, first #{min(byte_size(data), 32)} hex: #{preview})"
    )

    state
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
    case Jason.decode(json, floats: :decimals) do
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

  defp dispatch_message(
         %{"channel" => "executions", "type" => type_str, "data" => data, "sequence" => seq},
         state
       ) do
    type =
      case type_str do
        "snapshot" -> :snapshot
        "update" -> :update
      end

    Phoenix.PubSub.broadcast(
      state.pubsub,
      "executions",
      {:executions, %{type: type, data: data, sequence: seq}}
    )

    state
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
      | sub_reg: SubscriptionRegistry.mark_confirmed(state.sub_reg, result["channel"], nil)
    }
  end

  defp dispatch_message(
         %{"method" => "subscribe", "success" => false, "error" => "ESession:Invalid session"},
         state
       ) do
    retry_in_flight = Keyword.get(state.subscribe_opts, :_retry_in_flight, false)

    if retry_in_flight do
      # Second ESession error — retry already attempted. Trigger reconnect.
      Logger.warning("WebSocket.Private ESession:Invalid session on retry, reconnecting")

      trigger_reconnect(%{
        state
        | subscribe_opts: Keyword.delete(state.subscribe_opts, :_retry_in_flight)
      })
    else
      # First ESession error: sleep 100ms (per auth-refresh-race-telemetry memo),
      # re-read token, retry once. If the retry also fails, trigger reconnect.
      # The 100ms sleep is intentional — without it, the retry reads the same
      # stale token from Auth's state before the in-flight refresh Task completes.
      Process.sleep(100)
      retry_subscribe_executions(state, Keyword.delete(state.subscribe_opts, :_retry_in_flight))
    end
  end

  defp dispatch_message(
         %{"method" => "subscribe", "success" => false, "error" => error},
         state
       ) do
    Logger.warning("WebSocket.Private subscribe rejected error=#{error}")
    state
  end

  defp dispatch_message(
         %{"method" => "unsubscribe", "result" => result, "success" => true},
         state
       ) do
    %{
      state
      | sub_reg: SubscriptionRegistry.remove_desired(state.sub_reg, result["channel"], nil)
    }
  end

  defp dispatch_message(%{"channel" => "heartbeat"}, state), do: state
  defp dispatch_message(_msg, state), do: state

  # ── Subscribe / unsubscribe helpers ──────────────────────────────────────────

  # Reads a fresh token from Auth and sends the subscribe frame.
  # Token is read here, used immediately, and NOT stored in state.
  defp do_subscribe_executions(state, opts) do
    token = Auth.current_token(state.auth)
    payload = Wire.subscribe_executions_payload(token, opts)
    send_text_or_reconnect(state, payload)
  end

  # Called after the first ESession:Invalid session error.
  # Reads a fresh token, retries once. On second failure, triggers reconnect.
  # A `:retry_flag` message is used to avoid blocking the GenServer mailbox
  # during the 100ms sleep; however, since the sleep already happened in
  # dispatch_message (called from handle_info), we can act directly here.
  defp retry_subscribe_executions(state, opts) do
    token = Auth.current_token(state.auth)
    payload = Wire.subscribe_executions_payload(token, opts)

    case Connection.send_text(state.conn, state.websocket, state.ref, payload) do
      {:ok, {conn, ws}} ->
        # Send went out; mark state as "retry in flight". The response will
        # be processed by dispatch_message again. To avoid infinite retry
        # loops, we use a marker in subscribe_opts to signal retry-in-progress.
        # On the next ESession error (if opts has the marker), trigger reconnect.
        updated_opts = Keyword.put(opts, :_retry_in_flight, true)
        %{state | conn: conn, websocket: ws, subscribe_opts: updated_opts}

      {:error, _} ->
        trigger_reconnect(state)
    end
  end

  defp send_unsubscribe_executions(state) do
    token = Auth.current_token(state.auth)
    payload = Wire.unsubscribe_executions_payload(token)
    send_text_or_reconnect(state, payload)
  end

  defp send_text_or_reconnect(state, payload) do
    case Connection.send_text(state.conn, state.websocket, state.ref, payload) do
      {:ok, {conn, ws}} -> %{state | conn: conn, websocket: ws}
      {:error, _} -> trigger_reconnect(state)
    end
  end

  # ── Reconnection ───────────────────────────────────────────────────────────

  defp trigger_reconnect(state) do
    if state.conn, do: Connection.close(state.conn, state.websocket, state.ref)
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    if state.pong_timer, do: Process.cancel_timer(state.pong_timer)

    new_attempts = state.reconnect_attempts + 1
    schedule_reconnect_after(new_attempts, state.reconnect_backoff_ms)

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
        sub_reg: SubscriptionRegistry.clear_confirmed(state.sub_reg),
        status: :disconnected,
        reconnect_attempts: new_attempts
    }
  end

  defp schedule_reconnect(state) do
    new_attempts = state.reconnect_attempts + 1
    schedule_reconnect_after(new_attempts, state.reconnect_backoff_ms)
    %{state | reconnect_attempts: new_attempts}
  end

  defp schedule_reconnect_after(1, _backoff_ms) do
    # First attempt: instant reconnect.
    send(self(), :connect)
  end

  defp schedule_reconnect_after(_n, backoff_ms) do
    # Subsequent attempts: use configured backoff.
    Process.send_after(self(), :connect, backoff_ms)
  end

  defp resubscribe_on_reconnect(state) do
    desired = SubscriptionRegistry.resubscribe_list(state.sub_reg)

    if Map.has_key?(desired, "executions") do
      # Strip the retry-in-flight marker from opts before replaying.
      clean_opts = Keyword.delete(state.subscribe_opts, :_retry_in_flight)
      do_subscribe_executions(state, clean_opts)
    else
      state
    end
  end

  # ── Heartbeat ─────────────────────────────────────────────────────────────

  defp schedule_ping(state) do
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    timer = Process.send_after(self(), :send_ping, state.ping_interval_ms)
    %{state | ping_timer: timer}
  end

  # ── Config ────────────────────────────────────────────────────────────────

  defp default_ws_url do
    Application.get_env(
      :triskele_kraken_client,
      :private_ws_url,
      "wss://ws-auth.kraken.com/v2"
    )
  end
end
