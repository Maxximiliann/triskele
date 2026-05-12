defmodule Triskele.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "test.all": :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"],
      "test.all": ["test --cover"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "dialyzer/triskele.plt"},
      plt_add_apps: [:mix],
      ignore_warnings: "dialyzer/.dialyzer_ignore.exs",
      flags: [:error_handling, :underspecs]
    ]
  end
end
