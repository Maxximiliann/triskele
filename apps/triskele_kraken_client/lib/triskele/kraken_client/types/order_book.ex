defmodule Triskele.KrakenClient.Types.OrderBook do
  @moduledoc false

  alias Triskele.KrakenClient.Parsers

  @typedoc """
  A single price level in a book snapshot.

  In a snapshot all `qty` values are strictly positive — there are no
  deletions. Contrast with `BookUpdate.price_level` where `qty: 0`
  signals level removal.
  """
  @type price_level :: %{price: Decimal.t(), qty: Decimal.t()}

  @enforce_keys [:symbol, :bids, :asks, :checksum]
  defstruct [:symbol, :bids, :asks, :checksum, :timestamp]

  @type t :: %__MODULE__{
          symbol: String.t(),
          bids: [price_level()],
          asks: [price_level()],
          checksum: non_neg_integer(),
          timestamp: DateTime.t() | nil
        }

  @spec from_ws(map()) :: t()
  def from_ws(data) do
    %__MODULE__{
      symbol: data["symbol"],
      bids: parse_levels(data["bids"]),
      asks: parse_levels(data["asks"]),
      checksum: data["checksum"],
      timestamp: maybe_datetime(data["timestamp"])
    }
  end

  defp parse_levels(nil), do: []

  defp parse_levels(levels) when is_list(levels) do
    Enum.map(levels, fn level ->
      %{
        price: Parsers.decimal_from_term(level["price"]),
        qty: Parsers.decimal_from_term(level["qty"])
      }
    end)
  end

  defp maybe_datetime(nil), do: nil
  defp maybe_datetime(ts), do: Parsers.datetime_from_iso8601!(ts)
end
