defmodule Triskele.KrakenClient.Types.BookUpdate do
  @moduledoc false

  alias Triskele.KrakenClient.Parsers

  @typedoc """
  A single price level in a book update delta.

  `qty: 0` means the price level has been removed from the book.
  `qty > 0` means add or replace the level at this price.
  Phase 2 order book maintenance applies this semantic when folding
  deltas into local state before validating the CRC32 checksum.
  """
  @type price_level :: %{price: Decimal.t(), qty: Decimal.t()}

  @enforce_keys [:symbol, :bids, :asks, :checksum, :timestamp]
  defstruct [:symbol, :bids, :asks, :checksum, :timestamp]

  @type t :: %__MODULE__{
          symbol: String.t(),
          bids: [price_level()],
          asks: [price_level()],
          checksum: non_neg_integer(),
          timestamp: DateTime.t()
        }

  @spec from_ws(map()) :: t()
  def from_ws(data) do
    %__MODULE__{
      symbol: data["symbol"],
      bids: parse_levels(data["bids"]),
      asks: parse_levels(data["asks"]),
      checksum: data["checksum"],
      timestamp: Parsers.datetime_from_iso8601!(data["timestamp"])
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
end
