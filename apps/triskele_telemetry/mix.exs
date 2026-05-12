defmodule TriskeleTelemetry.MixProject do
  use Mix.Project

  def project do
    [
      app: :triskele_telemetry,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Triskele.Telemetry.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end
end
