defmodule Triskele.KrakenClient.REST do
  @moduledoc """
  Kraken spot REST API adapter.

  All Kraken communication flows through this module. Public endpoints
  (`/0/public/*`, no authentication, GET) use `public_get/1`. Private
  endpoints (`/0/private/*`, HMAC-signed, POST) use `private_post/2`,
  which consults `Nonce` for a monotonic nonce and `SecretKeeper` for the
  `{api_key, signature}` pair — the raw API secret never enters this
  module's process scope (Bible §2.1.5).

  Every request passes through `RateLimit.acquire/1` before hitting the
  network, honouring Kraken's Pro-tier token bucket (180 tokens, 3.75/s
  decay). HTTP transport is swappable via Application config key
  `:http_client`; in tests `Triskele.KrakenClient.HTTPClientMock` is
  injected via Mox so no real network calls are made.
  """

  alias Triskele.KrakenClient.Error
  alias Triskele.KrakenClient.Nonce
  alias Triskele.KrakenClient.Parsers
  alias Triskele.KrakenClient.RateLimit
  alias Triskele.KrakenClient.SecretKeeper
  alias Triskele.KrakenClient.Types.AddOrderRequest
  alias Triskele.KrakenClient.Types.AddOrderResponse
  alias Triskele.KrakenClient.Types.AssetPair
  alias Triskele.KrakenClient.Types.CancelOrderResponse
  alias Triskele.KrakenClient.Types.Order
  alias Triskele.KrakenClient.Types.TradeBalance

  @base_url "https://api.kraken.com"

  @spec get_server_time() :: {:ok, DateTime.t()} | {:error, Error.t()}
  def get_server_time do
    with {:ok, data} <- public_get("/0/public/Time") do
      {:ok, Parsers.datetime_from_unix(data["unixtime"])}
    end
  end

  @spec get_asset_pairs() :: {:ok, %{String.t() => AssetPair.t()}} | {:error, Error.t()}
  def get_asset_pairs do
    with {:ok, data} <- public_get("/0/public/AssetPairs") do
      pairs = Map.new(data, fn {symbol, info} -> {symbol, AssetPair.from_api(symbol, info)} end)
      {:ok, pairs}
    end
  end

  @spec get_balance() :: {:ok, %{String.t() => Decimal.t()}} | {:error, Error.t()}
  def get_balance do
    with {:ok, data} <- private_post("/0/private/Balance", %{}) do
      balances =
        Map.new(data, fn {asset, amount} -> {asset, Parsers.decimal_from_term(amount)} end)

      {:ok, balances}
    end
  end

  @spec get_trade_balance(asset :: String.t()) :: {:ok, TradeBalance.t()} | {:error, Error.t()}
  def get_trade_balance(asset) do
    with {:ok, data} <- private_post("/0/private/TradeBalance", %{"asset" => asset}) do
      {:ok, TradeBalance.from_api(data)}
    end
  end

  @spec add_order(AddOrderRequest.t()) :: {:ok, AddOrderResponse.t()} | {:error, Error.t()}
  def add_order(%AddOrderRequest{} = req) do
    with {:ok, data} <- private_post("/0/private/AddOrder", AddOrderRequest.to_params(req)) do
      {:ok, AddOrderResponse.from_api(data)}
    end
  end

  @spec cancel_order(txid :: String.t()) ::
          {:ok, CancelOrderResponse.t()} | {:error, Error.t()}
  def cancel_order(txid) when is_binary(txid) do
    with {:ok, data} <- private_post("/0/private/CancelOrder", %{"txid" => txid}) do
      {:ok, CancelOrderResponse.from_api(data)}
    end
  end

  @spec query_orders(txids :: [String.t()]) ::
          {:ok, %{String.t() => Order.t()}} | {:error, Error.t()}
  def query_orders([_ | _] = txids) when length(txids) <= 50 do
    params = %{"txid" => Enum.join(txids, ",")}

    with {:ok, data} <- private_post("/0/private/QueryOrders", params) do
      orders = Map.new(data, fn {txid, info} -> {txid, Order.from_api(txid, info)} end)
      {:ok, orders}
    end
  end

  @spec get_open_orders() :: {:ok, [Order.t()]} | {:error, Error.t()}
  def get_open_orders do
    with {:ok, data} <- private_post("/0/private/OpenOrders", %{}) do
      orders =
        data
        |> Map.get("open", %{})
        |> Enum.map(fn {txid, info} -> Order.from_api(txid, info) end)

      {:ok, orders}
    end
  end

  @spec get_websocket_token() :: {:ok, String.t()} | {:error, Error.t()}
  def get_websocket_token do
    with {:ok, data} <- private_post("/0/private/GetWebSocketsToken", %{}) do
      {:ok, Map.fetch!(data, "token")}
    end
  end

  defp public_get(path) do
    :ok = RateLimit.acquire(1)
    url = @base_url <> path

    with {:ok, 200, response_body} <- http_client().get(url, [{"Accept", "application/json"}]),
         {:ok, parsed} <- Jason.decode(response_body),
         :ok <- check_kraken_errors(parsed) do
      {:ok, parsed["result"]}
    else
      {:ok, status, response_body} ->
        {:error, Error.from_http_status(status, response_body)}

      {:error, %Error{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, Error.from_mint(reason)}
    end
  end

  # Assembles nonce, HMAC signature, headers, and POST body in one sequence.
  # Splitting the function would fragment the security-critical credential path,
  # making it harder to audit that no intermediate state leaks. Approved complexity.
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp private_post(path, params) when is_map(params) do
    false = Map.has_key?(params, "nonce")
    :ok = RateLimit.acquire(1)
    nonce = Nonce.next_nonce()
    form_params = Map.put(params, "nonce", Integer.to_string(nonce))
    body = URI.encode_query(form_params)
    {api_key, signature} = SecretKeeper.sign(path, nonce, body)

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "application/json"},
      {"API-Key", api_key},
      {"API-Sign", signature}
    ]

    url = @base_url <> path

    with {:ok, 200, response_body} <- http_client().post(url, headers, body),
         {:ok, parsed} <- Jason.decode(response_body),
         :ok <- check_kraken_errors(parsed) do
      {:ok, parsed["result"]}
    else
      {:ok, status, response_body} ->
        {:error, Error.from_http_status(status, response_body)}

      {:error, %Error{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, Error.from_mint(reason)}
    end
  end

  defp check_kraken_errors(%{"error" => []}), do: :ok

  defp check_kraken_errors(%{"error" => errors}) when errors != [],
    do: {:error, Error.from_kraken(errors)}

  defp check_kraken_errors(_), do: :ok

  defp http_client do
    Application.get_env(
      :triskele_kraken_client,
      :http_client,
      Triskele.KrakenClient.HTTPClient.Finch
    )
  end
end
