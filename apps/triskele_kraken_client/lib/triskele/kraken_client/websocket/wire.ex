defmodule Triskele.KrakenClient.WebSocket.Wire do
  @moduledoc """
  Pure functions for building Kraken WS v2 JSON request payloads.

  All functions accept Elixir terms and return JSON-encoded strings ready to
  be sent over the WebSocket. No state or side effects.
  """

  @spec subscribe_book_payload([String.t(), ...], pos_integer()) :: String.t()
  def subscribe_book_payload(symbols, depth) do
    Jason.encode!(%{
      "method" => "subscribe",
      "params" => %{"channel" => "book", "symbol" => symbols, "depth" => depth}
    })
  end

  @spec subscribe_ticker_payload([String.t(), ...]) :: String.t()
  def subscribe_ticker_payload(symbols) do
    Jason.encode!(%{
      "method" => "subscribe",
      "params" => %{"channel" => "ticker", "symbol" => symbols}
    })
  end

  @spec unsubscribe_payload(String.t(), [String.t(), ...]) :: String.t()
  def unsubscribe_payload(channel, symbols) do
    Jason.encode!(%{
      "method" => "unsubscribe",
      "params" => %{"channel" => channel, "symbol" => symbols}
    })
  end

  @spec ping_payload(integer()) :: String.t()
  def ping_payload(req_id) do
    Jason.encode!(%{"method" => "ping", "req_id" => req_id})
  end
end
