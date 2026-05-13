defmodule Triskele.KrakenClient.WebSocket.Auth do
  @moduledoc """
  Manages the WebSocket authentication token for Kraken's private channel.

  Fetches a token via `REST.get_websocket_token/0` at startup and refreshes
  it 5 minutes before it expires (Kraken tokens last 15 minutes). The
  current token is handed to the WebSocket process via `current_token/0`.

  If the REST call fails at startup, `init/1` returns `{:stop, reason}` —
  the supervisor will retry. After a successful boot, refresh failures log
  an error but do not crash the process; the previous token remains valid
  for the remainder of its window. Refresh runs in a spawned Task so the
  GenServer mailbox stays responsive during the REST round-trip.

  ## Boot ordering

  This process depends on `SecretKeeper`, `Nonce`, and `RateLimit` being
  started first. The Application supervisor's child list must place those
  before `WebSocket.Auth`. If they are started concurrently, `init/1`'s
  REST call will fail and the supervisor will retry until they come up —
  this works but is wasteful. Prefer explicit ordering in the child spec.

  ## Config

  `start_link/1` accepts one optional opt:

  - `:name` — GenServer registered name. Defaults to `__MODULE__`. Tests
    that need isolated instances pass a unique atom so each one registers
    under its own name.
  """

  use GenServer

  require Logger

  alias Triskele.KrakenClient.REST

  @token_lifetime_s 15 * 60
  @refresh_before_expiry_s 5 * 60
  @refresh_after_ms (@token_lifetime_s - @refresh_before_expiry_s) * 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec current_token(GenServer.server()) :: String.t()
  def current_token(server \\ __MODULE__) do
    GenServer.call(server, :current_token)
  end

  @impl GenServer
  def init(_opts) do
    case REST.get_websocket_token() do
      {:ok, token} ->
        schedule_refresh()
        {:ok, %{token: token}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:current_token, _from, state) do
    {:reply, state.token, state}
  end

  @impl GenServer
  def handle_info(:refresh_token, state) do
    parent = self()

    Task.start(fn ->
      send(parent, {:refresh_result, REST.get_websocket_token()})
    end)

    {:noreply, state}
  end

  def handle_info({:refresh_result, {:ok, token}}, state) do
    schedule_refresh()
    {:noreply, %{state | token: token}}
  end

  def handle_info({:refresh_result, {:error, reason}}, state) do
    # TODO Phase 2: replace with :telemetry.execute([:triskele, :kraken_client, :ws_auth_refresh_failed], ...)
    # once the telemetry hub exists. Per Bible §6, token refresh failure is
    # a meaningful event that should be observable. For now, Logger is a
    # temporary stand-in.
    Logger.error(
      "WebSocket.Auth token refresh failed: #{inspect(reason)}, retaining current token"
    )

    schedule_refresh()
    {:noreply, state}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_token, @refresh_after_ms)
  end
end
