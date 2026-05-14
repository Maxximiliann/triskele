defmodule Triskele.KrakenClient.WebSocket.SubscriptionRegistry do
  @moduledoc """
  Pure subscription state machine for WebSocket channel management.

  Tracks two sets:
  - `desired` — channels/symbols the caller has requested (survives reconnects)
  - `confirmed` — channels/symbols acknowledged by Kraken (cleared on disconnect)

  Sub-keys for symbol-bearing channels (book, ticker) are `{channel, symbol}`.
  Sub-keys for private channels without a symbol (executions, openOrders) are
  `{channel, nil}`.
  """

  @type channel :: String.t()
  @type symbol :: String.t() | nil
  @type sub_key :: {channel(), symbol()}

  @enforce_keys [:desired, :confirmed]
  defstruct desired: MapSet.new(), confirmed: MapSet.new()

  @type t :: %__MODULE__{
          desired: MapSet.t(sub_key()),
          confirmed: MapSet.t(sub_key())
        }

  @spec new() :: t()
  def new, do: %__MODULE__{desired: MapSet.new(), confirmed: MapSet.new()}

  @doc "Adds a subscription to the desired set."
  @spec add_desired(t(), channel(), symbol()) :: t()
  def add_desired(%__MODULE__{} = reg, channel, symbol) do
    %{reg | desired: MapSet.put(reg.desired, {channel, symbol})}
  end

  @doc "Moves a subscription from desired to confirmed."
  @spec mark_confirmed(t(), channel(), symbol()) :: t()
  def mark_confirmed(%__MODULE__{} = reg, channel, symbol) do
    %{reg | confirmed: MapSet.put(reg.confirmed, {channel, symbol})}
  end

  @doc "Removes a subscription from both sets (subscribe rejected or failed)."
  @spec mark_rejected(t(), channel(), symbol()) :: t()
  def mark_rejected(%__MODULE__{} = reg, channel, symbol) do
    key = {channel, symbol}

    %{
      reg
      | desired: MapSet.delete(reg.desired, key),
        confirmed: MapSet.delete(reg.confirmed, key)
    }
  end

  @doc "Removes a caller-requested unsubscription from both sets."
  @spec remove_desired(t(), channel(), symbol()) :: t()
  def remove_desired(%__MODULE__{} = reg, channel, symbol) do
    key = {channel, symbol}

    %{
      reg
      | desired: MapSet.delete(reg.desired, key),
        confirmed: MapSet.delete(reg.confirmed, key)
    }
  end

  @doc "Clears the confirmed set only. Called on disconnect; desired is preserved for reconnect."
  @spec clear_confirmed(t()) :: t()
  def clear_confirmed(%__MODULE__{} = reg) do
    %{reg | confirmed: MapSet.new()}
  end

  @doc "Clears confirmed state for a single subscription, leaving desired intact. Used on CRC mismatch to request a fresh snapshot without implying Kraken rejected the subscription."
  @spec unconfirm(t(), channel(), symbol()) :: t()
  def unconfirm(%__MODULE__{} = reg, channel, symbol) do
    %{reg | confirmed: MapSet.delete(reg.confirmed, {channel, symbol})}
  end

  @doc """
  Returns the desired subscriptions grouped by channel for batched re-subscription.

  Returns `%{channel => [symbol]}`. Used by `resubscribe_all` after reconnect.
  """
  @spec resubscribe_list(t()) :: %{channel() => [symbol()]}
  def resubscribe_list(%__MODULE__{desired: desired}) do
    Enum.group_by(desired, fn {ch, _sym} -> ch end, fn {_ch, sym} -> sym end)
  end
end
