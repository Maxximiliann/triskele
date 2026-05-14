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

  @doc """
  Builds a Kraken v2 subscribe payload for the `executions` private channel.

  `token` is the WebSocket auth token from `WebSocket.Auth.current_token/1`.
  `opts` accepts:
  - `:snap_orders` — boolean, default `true`
  - `:snap_trades` — boolean, default `false`
  - `:order_status` — boolean, default `true`
  """
  @spec subscribe_executions_payload(String.t(), keyword()) :: String.t()
  def subscribe_executions_payload(token, opts) do
    params = %{
      "channel" => "executions",
      "token" => token,
      "snap_orders" => Keyword.get(opts, :snap_orders, true),
      "snap_trades" => Keyword.get(opts, :snap_trades, false),
      "order_status" => Keyword.get(opts, :order_status, true)
    }

    Jason.encode!(%{"method" => "subscribe", "params" => params})
  end

  @doc """
  Builds a Kraken v2 unsubscribe payload for the `executions` private channel.

  Token is included per Kraken v2 private-channel convention — harmless on the
  success path even if Kraken does not require it.
  """
  @spec unsubscribe_executions_payload(String.t()) :: String.t()
  def unsubscribe_executions_payload(token) do
    Jason.encode!(%{
      "method" => "unsubscribe",
      "params" => %{"channel" => "executions", "token" => token}
    })
  end
end
