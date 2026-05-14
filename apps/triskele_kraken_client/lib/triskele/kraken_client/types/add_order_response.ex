defmodule Triskele.KrakenClient.Types.AddOrderResponse do
  @moduledoc false

  @enforce_keys [:txids, :description]
  defstruct [:txids, :description]

  @type t :: %__MODULE__{
          txids: [String.t()],
          description: String.t()
        }

  @spec from_api(map()) :: t()
  def from_api(data) do
    %__MODULE__{
      txids: Map.fetch!(data, "txid"),
      description: get_in(data, ["descr", "order"]) || ""
    }
  end
end
