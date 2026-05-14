defmodule Triskele.KrakenClient.Application do
  @moduledoc false

  use Application

  @impl Application
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children =
      if Application.get_env(:triskele_kraken_client, :start_supervision_tree, true) do
        [Triskele.KrakenClient.Supervisor]
      else
        []
      end

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Triskele.KrakenClient.AppSupervisor
    )
  end
end
