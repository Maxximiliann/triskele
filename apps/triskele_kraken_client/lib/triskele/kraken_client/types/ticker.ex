defmodule Triskele.KrakenClient.Types.Ticker do
  @moduledoc false

  alias Triskele.KrakenClient.Parsers

  @enforce_keys [:symbol]
  defstruct [
    :symbol,
    :bid,
    :bid_qty,
    :ask,
    :ask_qty,
    :last,
    :volume,
    :vwap,
    :low,
    :high,
    :change,
    :change_pct,
    :timestamp
  ]

  @type t :: %__MODULE__{
          symbol: String.t(),
          bid: Decimal.t() | nil,
          bid_qty: Decimal.t() | nil,
          ask: Decimal.t() | nil,
          ask_qty: Decimal.t() | nil,
          last: Decimal.t() | nil,
          volume: Decimal.t() | nil,
          vwap: Decimal.t() | nil,
          low: Decimal.t() | nil,
          high: Decimal.t() | nil,
          change: Decimal.t() | nil,
          change_pct: Decimal.t() | nil,
          timestamp: DateTime.t() | nil
        }

  @spec from_ws(map()) :: t()
  def from_ws(data) do
    %__MODULE__{
      symbol: data["symbol"],
      bid: Parsers.decimal_from_term(data["bid"]),
      bid_qty: Parsers.decimal_from_term(data["bid_qty"]),
      ask: Parsers.decimal_from_term(data["ask"]),
      ask_qty: Parsers.decimal_from_term(data["ask_qty"]),
      last: Parsers.decimal_from_term(data["last"]),
      volume: Parsers.decimal_from_term(data["volume"]),
      vwap: Parsers.decimal_from_term(data["vwap"]),
      low: Parsers.decimal_from_term(data["low"]),
      high: Parsers.decimal_from_term(data["high"]),
      change: Parsers.decimal_from_term(data["change"]),
      change_pct: Parsers.decimal_from_term(data["change_pct"]),
      timestamp: maybe_datetime(data["timestamp"])
    }
  end

  defp maybe_datetime(nil), do: nil
  defp maybe_datetime(ts), do: Parsers.datetime_from_iso8601!(ts)
end
