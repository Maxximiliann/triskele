defmodule Triskele.KrakenClient.Types.TradeBalance do
  @moduledoc """
  Response struct for the Kraken `/0/private/TradeBalance` REST endpoint.

  ## Spot-only constraint

  The fields `margin`, `unrealized_pnl`, `cost_basis`, `floating_valuation`,
  `equity`, and `free_margin` reflect Kraken's margin/futures account
  dimensions. They are modeled here for completeness but **must not be used
  in any trading decision in Triskele**. Triskele is spot-only (Bible §10).

  ## P&L source of truth

  P&L is computed by `Triskele.Portfolio` (Phase 4) from the sequence of
  filled orders recorded in the WAL, not from balance snapshots. A balance
  snapshot is a point-in-time watermark; it cannot attribute profit to
  individual cycles or account for in-flight legs. Do not use `trade_balance`
  or `equity` as a P&L signal.

  `equivalent_balance` and `trade_balance` are kept for boot-time sanity
  checks (confirming the account has non-zero spot equity before the engine
  is allowed to start) and for the operator dashboard display.
  """

  alias Triskele.KrakenClient.Parsers

  @enforce_keys [:equivalent_balance, :trade_balance]
  defstruct [
    :equivalent_balance,
    :trade_balance,
    :margin,
    :unrealized_pnl,
    :cost_basis,
    :floating_valuation,
    :equity,
    :free_margin
  ]

  @type t :: %__MODULE__{
          equivalent_balance: Decimal.t(),
          trade_balance: Decimal.t(),
          margin: Decimal.t() | nil,
          unrealized_pnl: Decimal.t() | nil,
          cost_basis: Decimal.t() | nil,
          floating_valuation: Decimal.t() | nil,
          equity: Decimal.t() | nil,
          free_margin: Decimal.t() | nil
        }

  @spec from_api(map()) :: t()
  def from_api(data) do
    %__MODULE__{
      equivalent_balance: Parsers.decimal_from_term(Map.fetch!(data, "eb")),
      trade_balance: Parsers.decimal_from_term(Map.fetch!(data, "tb")),
      margin: Parsers.decimal_from_term(data["m"]),
      unrealized_pnl: Parsers.decimal_from_term(data["n"]),
      cost_basis: Parsers.decimal_from_term(data["c"]),
      floating_valuation: Parsers.decimal_from_term(data["v"]),
      equity: Parsers.decimal_from_term(data["e"]),
      free_margin: Parsers.decimal_from_term(data["mf"])
    }
  end
end
