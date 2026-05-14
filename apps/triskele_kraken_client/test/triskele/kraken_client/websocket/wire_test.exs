defmodule Triskele.KrakenClient.WebSocket.WireTest do
  use ExUnit.Case, async: true

  alias Triskele.KrakenClient.WebSocket.Wire

  @moduletag :phase_1

  describe "subscribe_book_payload/2" do
    test "encodes method, channel, symbols, and depth" do
      json = Wire.subscribe_book_payload(["BTC/USD", "ETH/USD"], 10)
      decoded = Jason.decode!(json)

      assert decoded["method"] == "subscribe"
      assert decoded["params"]["channel"] == "book"
      assert decoded["params"]["symbol"] == ["BTC/USD", "ETH/USD"]
      assert decoded["params"]["depth"] == 10
    end

    test "depth is encoded as an integer, not a string" do
      json = Wire.subscribe_book_payload(["BTC/USD"], 25)
      decoded = Jason.decode!(json)

      assert is_integer(decoded["params"]["depth"])
      assert decoded["params"]["depth"] == 25
    end
  end

  describe "subscribe_ticker_payload/1" do
    test "encodes method, channel, and symbols" do
      json = Wire.subscribe_ticker_payload(["SOL/USD"])
      decoded = Jason.decode!(json)

      assert decoded["method"] == "subscribe"
      assert decoded["params"]["channel"] == "ticker"
      assert decoded["params"]["symbol"] == ["SOL/USD"]
    end

    test "does not include depth field" do
      json = Wire.subscribe_ticker_payload(["BTC/USD"])
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded["params"], "depth")
    end
  end

  describe "unsubscribe_payload/2" do
    test "encodes unsubscribe method with channel and symbols" do
      json = Wire.unsubscribe_payload("ticker", ["BTC/USD", "ETH/USD"])
      decoded = Jason.decode!(json)

      assert decoded["method"] == "unsubscribe"
      assert decoded["params"]["channel"] == "ticker"
      assert decoded["params"]["symbol"] == ["BTC/USD", "ETH/USD"]
    end

    test "works for book channel" do
      json = Wire.unsubscribe_payload("book", ["BTC/USD"])
      decoded = Jason.decode!(json)

      assert decoded["method"] == "unsubscribe"
      assert decoded["params"]["channel"] == "book"
    end
  end

  describe "ping_payload/1" do
    test "encodes method and req_id" do
      json = Wire.ping_payload(42)
      decoded = Jason.decode!(json)

      assert decoded["method"] == "ping"
      assert decoded["req_id"] == 42
    end

    test "req_id is encoded as an integer" do
      json = Wire.ping_payload(999)
      decoded = Jason.decode!(json)

      assert is_integer(decoded["req_id"])
    end
  end
end
