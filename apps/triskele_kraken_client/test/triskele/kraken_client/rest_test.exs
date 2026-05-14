defmodule Triskele.KrakenClient.RESTTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Mox

  alias Triskele.KrakenClient.HTTPClientMock
  alias Triskele.KrakenClient.Nonce
  alias Triskele.KrakenClient.RateLimit
  alias Triskele.KrakenClient.REST
  alias Triskele.KrakenClient.SecretKeeper

  @moduletag :phase_1

  # Valid base64 test secret (decodes to "test_secret_base64_encoded").
  # Must be valid base64 — Signing.sign/4 calls Base.decode64! on it.
  @test_secret "dGVzdF9zZWNyZXRfYmFzZTY0X2VuY29kZWQ="

  setup :verify_on_exit!

  setup do
    dets_path =
      Path.join(System.tmp_dir!(), "rest_test_nonce_#{System.unique_integer([:positive])}.dets")

    Application.put_env(:triskele_kraken_client, :nonce_dets_path, dets_path)
    Application.put_env(:triskele_kraken_client, :http_client, HTTPClientMock)
    Application.put_env(:triskele_kraken_client, :api_key, "test_key")
    Application.put_env(:triskele_kraken_client, :api_secret, @test_secret)

    start_supervised!({Nonce, []})
    start_supervised!({RateLimit, []})
    start_supervised!({SecretKeeper, []})

    on_exit(fn ->
      Application.delete_env(:triskele_kraken_client, :nonce_dets_path)
      Application.delete_env(:triskele_kraken_client, :http_client)
      Application.delete_env(:triskele_kraken_client, :api_key)
      Application.delete_env(:triskele_kraken_client, :api_secret)
      File.rm(dets_path)
    end)

    :ok
  end

  defp ok_response(result) do
    body = Jason.encode!(%{"error" => [], "result" => result})
    {:ok, 200, body}
  end

  defp kraken_error_response(errors) do
    body = Jason.encode!(%{"error" => errors})
    {:ok, 200, body}
  end

  describe "get_server_time/0" do
    test "returns a DateTime on success" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        ok_response(%{"unixtime" => 1_616_492_376, "rfc1123" => "Mon, 23 Mar 21 14:39:36 +0000"})
      end)

      assert {:ok, %DateTime{} = dt} = REST.get_server_time()
      assert dt.year == 2021
    end

    test "returns server_error on Kraken EGeneral:Internal error" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        kraken_error_response(["EGeneral:Internal error"])
      end)

      assert {:error, err} = REST.get_server_time()
      assert err.kind == :server_error
    end

    test "returns server_error on HTTP 503 with retryable true" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        {:ok, 503, "Service Unavailable"}
      end)

      assert {:error, err} = REST.get_server_time()
      assert err.kind == :server_error
      assert err.retryable == true
      assert err.raw == {503, "Service Unavailable"}
    end

    test "returns invalid_arguments on HTTP 400" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        {:ok, 400, "Bad Request"}
      end)

      assert {:error, err} = REST.get_server_time()
      assert err.kind == :invalid_arguments
      assert err.retryable == false
    end

    test "returns network_timeout on Mint transport timeout" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      assert {:error, err} = REST.get_server_time()
      assert err.kind == :network_timeout
      assert err.retryable == true
    end
  end

  describe "get_asset_pairs/0" do
    test "parses asset pairs into a map of AssetPair structs" do
      pair_data = %{
        "base" => "XXBT",
        "quote" => "ZUSD",
        "status" => "online",
        "lot_decimals" => 8,
        "pair_decimals" => 1,
        "costmin" => "0.5",
        "ordermin" => "0.0001",
        "tick_size" => "0.1",
        "fees" => [[0, 0.26]],
        "fees_maker" => [[0, 0.16]]
      }

      expect(HTTPClientMock, :get, fn _url, _headers ->
        ok_response(%{"XXBTZUSD" => pair_data})
      end)

      assert {:ok, pairs} = REST.get_asset_pairs()
      assert map_size(pairs) == 1
      assert %Triskele.KrakenClient.Types.AssetPair{} = pairs["XXBTZUSD"]
      assert pairs["XXBTZUSD"].base == "XXBT"
      assert pairs["XXBTZUSD"].quote == "ZUSD"
    end

    test "returns error on Kraken error" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        kraken_error_response(["EGeneral:Internal error"])
      end)

      assert {:error, _} = REST.get_asset_pairs()
    end
  end

  describe "get_balance/0" do
    test "returns balance map with Decimal values" do
      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"XXBT" => "1.25000000", "ZUSD" => "10000.00"})
      end)

      assert {:ok, balances} = REST.get_balance()
      assert %Decimal{} = balances["XXBT"]
      assert Decimal.equal?(balances["XXBT"], Decimal.new("1.25000000"))
      assert Decimal.equal?(balances["ZUSD"], Decimal.new("10000.00"))
    end

    test "returns rate_limited error on EAPI:Rate limit exceeded" do
      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        kraken_error_response(["EAPI:Rate limit exceeded"])
      end)

      assert {:error, err} = REST.get_balance()
      assert err.kind == :rate_limited
      assert err.retryable == true
    end
  end

  describe "add_order/1" do
    test "returns AddOrderResponse with txids on success" do
      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{
          "txid" => ["OXXXXX-XXXXX-XXXXX"],
          "descr" => %{"order" => "buy 1.25000000 XBTUSD @ limit 37500.00"}
        })
      end)

      req = %Triskele.KrakenClient.Types.AddOrderRequest{
        pair: "XBTUSD",
        type: :buy,
        order_type: :limit,
        volume: Decimal.new("1.25"),
        price: Decimal.new("37500")
      }

      assert {:ok, resp} = REST.add_order(req)
      assert resp.txids == ["OXXXXX-XXXXX-XXXXX"]
      assert resp.description == "buy 1.25000000 XBTUSD @ limit 37500.00"
    end

    test "returns rate_limited error on EAPI:Rate limit exceeded" do
      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        kraken_error_response(["EAPI:Rate limit exceeded"])
      end)

      req = %Triskele.KrakenClient.Types.AddOrderRequest{
        pair: "XBTUSD",
        type: :buy,
        order_type: :limit,
        volume: Decimal.new("1.25"),
        price: Decimal.new("37500")
      }

      assert {:error, err} = REST.add_order(req)
      assert err.kind == :rate_limited
    end

    test "returns insufficient_funds error on EOrder:Insufficient funds" do
      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        kraken_error_response(["EOrder:Insufficient funds"])
      end)

      req = %Triskele.KrakenClient.Types.AddOrderRequest{
        pair: "XBTUSD",
        type: :buy,
        order_type: :limit,
        volume: Decimal.new("1.25"),
        price: Decimal.new("37500")
      }

      assert {:error, err} = REST.add_order(req)
      assert err.kind == :insufficient_funds
      assert err.retryable == false
    end
  end

  describe "cancel_order/1" do
    test "returns CancelOrderResponse with count on success" do
      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"count" => 1})
      end)

      assert {:ok, resp} = REST.cancel_order("OXXXXX-XXXXX-XXXXX")
      assert resp.count == 1
    end
  end

  describe "query_orders/1" do
    test "returns map of Order structs on success" do
      order_data = %{
        "status" => "open",
        "descr" => %{
          "pair" => "XBTUSD",
          "type" => "buy",
          "ordertype" => "limit",
          "price" => "37500",
          "price2" => "0"
        },
        "vol" => "1.25000000",
        "vol_exec" => "0.00000000",
        "cost" => "0.00000",
        "fee" => "0.00000",
        "price" => "0.00000",
        "stopprice" => "0.00000",
        "limitprice" => "0.00000",
        "misc" => "",
        "oflags" => "fciq",
        "opentm" => 1_616_000_000.0
      }

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"OXXXXX-XXXXX-XXXXX" => order_data})
      end)

      assert {:ok, orders} = REST.query_orders(["OXXXXX-XXXXX-XXXXX"])

      assert %Triskele.KrakenClient.Types.Order{txid: "OXXXXX-XXXXX-XXXXX"} =
               orders["OXXXXX-XXXXX-XXXXX"]
    end

    test "raises FunctionClauseError for empty list" do
      assert_raise FunctionClauseError, fn -> REST.query_orders([]) end
    end

    test "raises FunctionClauseError for list of 51 txids" do
      assert_raise FunctionClauseError, fn ->
        REST.query_orders(Enum.map(1..51, &"ORDER-#{&1}"))
      end
    end
  end

  describe "get_open_orders/0" do
    test "returns list of Order structs" do
      order_data = %{
        "status" => "open",
        "descr" => %{
          "pair" => "XBTUSD",
          "type" => "sell",
          "ordertype" => "limit",
          "price" => "40000",
          "price2" => "0"
        },
        "vol" => "0.50000000",
        "vol_exec" => "0.00000000",
        "cost" => "0.00000",
        "fee" => "0.00000",
        "price" => "0.00000",
        "stopprice" => "0.00000",
        "limitprice" => "0.00000",
        "misc" => "",
        "oflags" => "fciq",
        "opentm" => 1_616_000_000.0
      }

      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"open" => %{"OYYYYY-YYYYY-YYYYY" => order_data}})
      end)

      assert {:ok, orders} = REST.get_open_orders()
      assert [%Triskele.KrakenClient.Types.Order{txid: "OYYYYY-YYYYY-YYYYY"}] = orders
    end

    test "returns empty list when no open orders" do
      expect(HTTPClientMock, :post, fn _url, _headers, _body ->
        ok_response(%{"open" => %{}})
      end)

      assert {:ok, []} = REST.get_open_orders()
    end
  end
end
