defmodule TriskeleCommon.MixProject do
  use Mix.Project

  def project do
    [
      app: :triskele_common,
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

  # Library-style OTP app: no mod: — no Application callback, no supervision tree.
  # All deps (tzdata, etc.) start their own supervision via their own applications.
  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # Required for DateTime.shift_zone!/2 in Triskele.Util.Time
      {:tzdata, "~> 1.1"}
    ]
  end
end
