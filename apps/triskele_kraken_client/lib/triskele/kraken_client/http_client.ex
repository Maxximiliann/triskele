defmodule Triskele.KrakenClient.HTTPClient do
  @moduledoc """
  Behaviour for HTTP transport against the Kraken REST API.

  Implementations:
    - `Triskele.KrakenClient.HTTPClient.Finch` — production, uses the named
      Finch pool `Triskele.KrakenClient.Finch` (HTTP/2, 4 connections, 15s
      request timeout).
    - `Triskele.KrakenClient.HTTPClientMock` — Mox-defined, used in tests.

  The behaviour exists so the REST module and its callers can be tested
  without network access. The real and mock implementations are
  interchangeable from the REST module's perspective; the choice is wired
  via Application config at boot:

      config :triskele_kraken_client, :http_client, Triskele.KrakenClient.HTTPClient.Finch

  # TODO: Per-request timeout overrides
  The current callback shape has no `opts` parameter, so the 15-second
  timeout from the Finch pool applies uniformly to every request. Phase 3
  (execution) leg-submission and Phase 4 (risk) latency-sensitive checks
  may require shorter per-call timeouts. When that need arises, grow the
  callbacks to:

      @callback get(url, headers, opts :: keyword()) :: ...
      @callback post(url, headers, body, opts :: keyword()) :: ...

  and thread `receive_timeout:` through to `Finch.request/3`. Until then,
  15s is a safe default — it is well above Kraken's typical p99 latency
  and well below any leg expiry budget.
  """

  @callback get(url :: String.t(), headers :: [{String.t(), String.t()}]) ::
              {:ok, status :: non_neg_integer(), body :: binary()} | {:error, term()}

  @callback post(
              url :: String.t(),
              headers :: [{String.t(), String.t()}],
              body :: binary()
            ) ::
              {:ok, status :: non_neg_integer(), body :: binary()} | {:error, term()}
end
