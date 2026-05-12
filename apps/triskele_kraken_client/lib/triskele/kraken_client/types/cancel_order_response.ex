defmodule Triskele.KrakenClient.Types.CancelOrderResponse do
  @moduledoc false

  @enforce_keys [:count]
  defstruct [:count, :pending]

  @type t :: %__MODULE__{
          count: non_neg_integer(),
          pending: boolean() | nil
        }

  @spec from_api(map()) :: t()
  def from_api(data) do
    %__MODULE__{
      count: Map.fetch!(data, "count"),
      pending: data["pending"]
    }
  end
end
