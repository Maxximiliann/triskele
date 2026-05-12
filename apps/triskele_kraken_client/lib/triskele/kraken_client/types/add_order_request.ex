defmodule Triskele.KrakenClient.Types.AddOrderRequest do
  @moduledoc false

  @enforce_keys [:pair, :type, :order_type, :volume]
  defstruct [
    :pair,
    :type,
    :order_type,
    :volume,
    :price,
    :price2,
    :expire_tm,
    :user_ref,
    :client_order_id,
    :flags
  ]

  @type order_type ::
          :limit
          | :market
          | :stop_loss
          | :stop_loss_limit
          | :take_profit
          | :take_profit_limit

  @typedoc """
  Order expiry as a Unix timestamp in **seconds** (not milliseconds).

  Kraken's `expiretm` REST parameter expects integer seconds since the Unix
  epoch. Passing a value in milliseconds would set an expiry ~1000× further
  in the future than intended — the order would effectively never expire
  within a trading session.

  Phase 1 prompt pitfall: "'expiretm' is Unix seconds, not milliseconds."

  The execution layer (Phase 3) is responsible for computing this value
  correctly from a `DateTime` or a relative duration. This type exists to
  make the contract explicit at the boundary.
  """
  @type unix_seconds :: pos_integer()

  @type t :: %__MODULE__{
          pair: String.t(),
          type: :buy | :sell,
          order_type: order_type(),
          volume: Decimal.t(),
          price: Decimal.t() | nil,
          price2: Decimal.t() | nil,
          expire_tm: unix_seconds() | nil,
          user_ref: integer() | nil,
          client_order_id: String.t() | nil,
          flags: [String.t()] | nil
        }

  # Encodes every optional order field into Kraken's form-encoded param map.
  # The maybe_put pipeline is flat and data-driven; extracting groups would
  # obscure which fields are always-present vs optional. Approved complexity.
  @spec to_params(t()) :: %{String.t() => String.t()}
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  def to_params(%__MODULE__{} = req) do
    base = %{
      "pair" => req.pair,
      "type" => Atom.to_string(req.type),
      "ordertype" => order_type_string(req.order_type),
      "volume" => Decimal.to_string(req.volume)
    }

    base
    |> maybe_put("price", req.price, &Decimal.to_string/1)
    |> maybe_put("price2", req.price2, &Decimal.to_string/1)
    |> maybe_put("expiretm", req.expire_tm, &Integer.to_string/1)
    |> maybe_put("userref", req.user_ref, &Integer.to_string/1)
    |> maybe_put("cl_ord_id", req.client_order_id, & &1)
    |> maybe_put("oflags", req.flags, &Enum.join(&1, ","))
  end

  defp order_type_string(:limit), do: "limit"
  defp order_type_string(:market), do: "market"
  defp order_type_string(:stop_loss), do: "stop-loss"
  defp order_type_string(:stop_loss_limit), do: "stop-loss-limit"
  defp order_type_string(:take_profit), do: "take-profit"
  defp order_type_string(:take_profit_limit), do: "take-profit-limit"

  defp maybe_put(map, _key, nil, _fun), do: map
  defp maybe_put(map, key, value, fun), do: Map.put(map, key, fun.(value))
end
