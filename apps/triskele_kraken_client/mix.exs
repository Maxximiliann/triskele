defmodule TriskeleKrakenClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :triskele_kraken_client,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {Triskele.KrakenClient.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:finch, "~> 0.19"},
      {:mint_web_socket, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
