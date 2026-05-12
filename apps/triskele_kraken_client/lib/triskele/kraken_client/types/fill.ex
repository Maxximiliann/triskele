defmodule Triskele.KrakenClient.Types.Fill do
  @moduledoc false

  alias Triskele.KrakenClient.Parsers

  @enforce_keys [:trade_id, :order_txid, :pair, :type, :price, :volume, :fee, :executed_at]
  defstruct [
    :trade_id,
    :order_txid,
    :pair,
    :type,
    :price,
    :volume,
    :fee,
    :cost,
    :executed_at
  ]

  @type t :: %__MODULE__{
          trade_id: String.t(),
          order_txid: String.t(),
          pair: String.t(),
          type: :buy | :sell,
          price: Decimal.t(),
          volume: Decimal.t(),
          fee: Decimal.t(),
          cost: Decimal.t() | nil,
          executed_at: DateTime.t()
        }

  @spec from_api(String.t(), map()) :: t()
  def from_api(trade_id, data) do
    %__MODULE__{
      trade_id: trade_id,
      order_txid: data["ordertxid"],
      pair: data["pair"],
      type: parse_side(data["type"]),
      price: Parsers.decimal_from_term(data["price"]),
      volume: Parsers.decimal_from_term(data["vol"]),
      fee: Parsers.decimal_from_term(data["fee"]),
      cost: Parsers.decimal_from_term(data["cost"]),
      executed_at: Parsers.datetime_from_unix(trunc(data["time"]))
    }
  end

  defp parse_side("buy"), do: :buy
  defp parse_side("sell"), do: :sell
end
