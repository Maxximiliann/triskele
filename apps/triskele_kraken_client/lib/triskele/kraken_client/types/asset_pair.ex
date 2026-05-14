defmodule Triskele.KrakenClient.Types.AssetPair do
  @moduledoc false

  alias Triskele.KrakenClient.Parsers

  @enforce_keys [:symbol, :base, :quote, :status, :lot_decimals, :pair_decimals]
  defstruct [
    :symbol,
    :base,
    :quote,
    :status,
    :lot_decimals,
    :pair_decimals,
    :cost_min,
    :order_min,
    :tick_size,
    :fees,
    :fees_maker
  ]

  @type t :: %__MODULE__{
          symbol: String.t(),
          base: String.t(),
          quote: String.t(),
          status: String.t(),
          lot_decimals: non_neg_integer(),
          pair_decimals: non_neg_integer(),
          cost_min: Decimal.t() | nil,
          order_min: Decimal.t() | nil,
          tick_size: Decimal.t() | nil,
          fees: [[Decimal.t()]] | nil,
          fees_maker: [[Decimal.t()]] | nil
        }

  @spec from_api(String.t(), map()) :: t()
  def from_api(symbol, data) do
    %__MODULE__{
      symbol: symbol,
      base: data["base"],
      quote: data["quote"],
      status: data["status"],
      lot_decimals: data["lot_decimals"],
      pair_decimals: data["pair_decimals"],
      cost_min: Parsers.decimal_from_term(data["costmin"]),
      order_min: Parsers.decimal_from_term(data["ordermin"]),
      tick_size: Parsers.decimal_from_term(data["tick_size"]),
      fees: parse_fee_schedule(data["fees"]),
      fees_maker: parse_fee_schedule(data["fees_maker"])
    }
  end

  defp parse_fee_schedule(nil), do: nil

  defp parse_fee_schedule(schedule) when is_list(schedule) do
    Enum.map(schedule, fn [vol, fee] ->
      [Parsers.decimal_from_term(vol), Parsers.decimal_from_term(fee)]
    end)
  end
end
