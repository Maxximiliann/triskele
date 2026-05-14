required_apps = [:phoenix_pubsub, :mox]

started = Enum.map(Application.started_applications(), &elem(&1, 0))

case required_apps -- started do
  [] ->
    :ok

  missing ->
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(
      :stderr,
      """
      [triskele_kraken_client/test_helper] required OTP application(s) not started: #{inspect(missing)}.
      Declared in apps/triskele_kraken_client/mix.exs `extra_applications(:test)`.
      Likely cause: stale `_build/` cache restored a `.app` file with an outdated
      `applications` tuple, or the `:extra_applications` declaration was not picked up
      by the umbrella test boot path. Failing loud at boot instead of as scattered
      downstream `start_supervised!` errors.
      """
    )

    System.halt(1)
end

ExUnit.start()
Mox.defmock(Triskele.KrakenClient.HTTPClientMock, for: Triskele.KrakenClient.HTTPClient)
