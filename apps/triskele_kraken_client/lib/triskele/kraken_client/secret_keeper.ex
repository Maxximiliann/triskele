defmodule Triskele.KrakenClient.SecretKeeper do
  @moduledoc """
  Holds KRAKEN_API_KEY and KRAKEN_API_SECRET in a sensitive process.

  This is the **only** process in Triskele that ever holds the raw API
  secret. It calls `Process.flag(:sensitive, true)` at startup, which
  excludes this process from `:erlang.process_info/1`, crash dumps,
  `:observer`, and `:recon` inspection (BEAM OTP-25+).

  The secret never leaves this process. REST callers obtain `{api_key,
  signature}` via `sign/3` — the HMAC computation happens inside this
  GenServer and only the finished signature is returned.

  See Bible §2.1.5 and `Triskele.KrakenClient.Signing` for the algorithm.

  ## Test injection

  In tests, credentials can be injected via Application config to avoid
  requiring real Kraken environment variables:

      Application.put_env(:triskele_kraken_client, :api_key, "test_key")
      Application.put_env(:triskele_kraken_client, :api_secret, "dGVzdF9zZWNyZXQ=")

  The `:api_secret` value must be a valid Base64 string (it is decoded
  before use in HMAC). Production reads from `KRAKEN_API_KEY` and
  `KRAKEN_API_SECRET` environment variables when the config keys are absent.

  ## Telemetry note

  The telemetry hub must never log or inspect this process's state. Any
  telemetry event emitted from here must not include the api_key,
  api_secret, or any derivative (e.g. partial signature bytes).
  """

  use GenServer

  alias Triskele.KrakenClient.Signing

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Signs a private REST request inside the keeper process.

  Returns `{api_key, signature}`. The raw secret never leaves this
  process. See `Triskele.KrakenClient.Signing.sign/4` for the algorithm.
  """
  @spec sign(path :: String.t(), nonce :: integer(), body :: String.t()) ::
          {api_key :: String.t(), signature :: String.t()}
  def sign(path, nonce, body) do
    GenServer.call(__MODULE__, {:sign, path, nonce, body})
  end

  @impl GenServer
  def init(_opts) do
    Process.flag(:sensitive, true)

    api_key =
      Application.get_env(:triskele_kraken_client, :api_key) ||
        System.fetch_env!("KRAKEN_API_KEY")

    api_secret =
      Application.get_env(:triskele_kraken_client, :api_secret) ||
        System.fetch_env!("KRAKEN_API_SECRET")

    {:ok, %{api_key: api_key, api_secret: api_secret}}
  end

  @impl GenServer
  def handle_call({:sign, path, nonce, body}, _from, %{api_key: key, api_secret: secret} = state) do
    signature = Signing.sign(path, nonce, body, secret)
    {:reply, {key, signature}, state}
  end
end
