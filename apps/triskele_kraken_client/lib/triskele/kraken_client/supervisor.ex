defmodule Triskele.KrakenClient.Supervisor do
  @moduledoc """
  Supervisor for the Kraken client subsystem. Strategy: `:one_for_one`.

  ## Boot order

  Children are started in the listed order. The order matters: Finch boots
  first; Auth's REST token fetch depends on the `Triskele.KrakenClient.Finch`
  named pool being available before `Auth.init/1` runs. SecretKeeper, Nonce,
  and RateLimit must be running before Auth can fetch its first WebSocket
  token. Phoenix.PubSub must be running before WebSocket.Public and
  WebSocket.Private (both broadcast to it).

  ## Restart policy

  Strategy is `:one_for_one`. If Auth crashes, Private may observe `:noproc`
  on its next `Auth.current_token/1` call (subscribe or resubscribe path)
  and will itself crash; the supervisor restarts Private. This is
  intentional Phase 1 behavior — defensive `try/catch` in Private would
  muddy the token-contract semantics and obscure crash-recovery in
  operator dashboards.
  """

  use Supervisor

  alias Triskele.KrakenClient.Nonce
  alias Triskele.KrakenClient.RateLimit
  alias Triskele.KrakenClient.SecretKeeper
  alias Triskele.KrakenClient.WebSocket.Auth
  alias Triskele.KrakenClient.WebSocket.Private
  alias Triskele.KrakenClient.WebSocket.Public

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      {Finch,
       name: Triskele.KrakenClient.Finch,
       pools: %{
         "https://api.kraken.com" => [size: 4, count: 1, protocols: [:http2]]
       }},
      SecretKeeper,
      Nonce,
      RateLimit,
      Auth,
      {Phoenix.PubSub, name: Triskele.PubSub},
      Public,
      Private
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
