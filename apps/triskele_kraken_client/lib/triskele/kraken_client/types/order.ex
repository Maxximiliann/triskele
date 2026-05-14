defmodule Triskele.KrakenClient.Types.Order do
  @moduledoc """
  Represents a single Kraken REST API order.

  ## Price field semantics

  Kraken returns two different price concepts in the same response object,
  which makes the mapping non-obvious:

  - `price`       — the limit price the order was placed at (`descr.price`
                    in the raw response). For market orders this is "0".
  - `avg_price`   — volume-weighted average fill price across all trades that
                    have executed against this order (`data["price"]` at the
                    top level of the order object, *not* inside `descr`).
                    Zero until at least one fill occurs.
  - `stop_price`  — the trigger price for stop-loss and stop-loss-limit
                    orders (`data["stopprice"]`).
  - `limit_price` — the secondary limit price for stop-limit and
                    take-profit-limit orders (`data["limitprice"]`). This is
                    the price at which the limit leg executes after the stop
                    triggers.

  Field names were verified against the beldur/kraken-go-api-client Go
  library (types.go). Confirm against a live API response during the Phase 1
  smoke test — particularly that `data["price"]` is indeed the avg fill price.
  """

  alias Triskele.KrakenClient.Parsers

  @enforce_keys [:txid, :pair, :type, :order_type, :status]
  defstruct [
    :txid,
    :pair,
    :type,
    :order_type,
    :status,
    :price,
    :price2,
    :volume,
    :volume_executed,
    :cost,
    :fee,
    :avg_price,
    :stop_price,
    :limit_price,
    :opened_at,
    :closed_at,
    :expiry,
    :user_ref,
    :client_order_id,
    :misc,
    :flags
  ]

  @type t :: %__MODULE__{
          txid: String.t(),
          pair: String.t(),
          type: :buy | :sell,
          order_type: String.t(),
          status: String.t(),
          price: Decimal.t() | nil,
          price2: Decimal.t() | nil,
          volume: Decimal.t() | nil,
          volume_executed: Decimal.t() | nil,
          cost: Decimal.t() | nil,
          fee: Decimal.t() | nil,
          avg_price: Decimal.t() | nil,
          stop_price: Decimal.t() | nil,
          limit_price: Decimal.t() | nil,
          opened_at: DateTime.t() | nil,
          closed_at: DateTime.t() | nil,
          expiry: DateTime.t() | nil,
          user_ref: integer() | nil,
          client_order_id: String.t() | nil,
          misc: String.t() | nil,
          flags: String.t() | nil
        }

  # One-to-one mapping from Kraken's flat REST response to a typed struct.
  # Complexity comes from field count (17 fields), not logic branches. Extracting
  # sub-mappers would scatter a single straightforward translation. Approved complexity.
  @spec from_api(String.t(), map()) :: t()
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  def from_api(txid, data) do
    desc = data["descr"] || %{}

    %__MODULE__{
      txid: txid,
      pair: desc["pair"],
      type: parse_side(desc["type"]),
      order_type: desc["ordertype"],
      status: data["status"],
      price: Parsers.decimal_from_term(desc["price"]),
      price2: Parsers.decimal_from_term(desc["price2"]),
      volume: Parsers.decimal_from_term(data["vol"]),
      volume_executed: Parsers.decimal_from_term(data["vol_exec"]),
      cost: Parsers.decimal_from_term(data["cost"]),
      fee: Parsers.decimal_from_term(data["fee"]),
      avg_price: Parsers.decimal_from_term(data["price"]),
      stop_price: Parsers.decimal_from_term(data["stopprice"]),
      limit_price: Parsers.decimal_from_term(data["limitprice"]),
      opened_at: maybe_unix(data["opentm"]),
      closed_at: maybe_unix(data["closetm"]),
      expiry: maybe_unix(data["expiretm"]),
      user_ref: data["userref"],
      client_order_id: data["cl_ord_id"],
      misc: data["misc"],
      flags: data["oflags"]
    }
  end

  defp parse_side("buy"), do: :buy
  defp parse_side("sell"), do: :sell

  defp maybe_unix(nil), do: nil
  defp maybe_unix(ts) when is_number(ts) and ts == 0, do: nil

  defp maybe_unix(ts) when is_number(ts) do
    Parsers.datetime_from_unix(trunc(ts))
  end
end
