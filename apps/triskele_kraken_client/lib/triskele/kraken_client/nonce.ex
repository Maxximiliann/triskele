defmodule Triskele.KrakenClient.Nonce do
  @moduledoc "Public API"

  use GenServer

  @default_dets_path "~/.local/share/triskele/nonce.dets"
  @dets_table :kraken_nonce

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the next monotonically increasing nonce for Kraken private API calls.

  The nonce is seeded from `:os.system_time(:millisecond)` at startup, or
  last-persisted-nonce + 1, whichever is greater. Subsequent calls increment
  by 1, ensuring strict monotonicity under concurrent access.

  ## Nonce errors

  Per the Phase 1 prompt pitfall: `EAPI:Invalid nonce` from Kraken is
  non-recoverable without operator intervention. It can occur if the DETS
  file is corrupted or the system clock jumps backward significantly. When
  this error is received, `Triskele.KrakenClient.Error` classifies it as
  `kind: :nonce_invalid, retryable: false` and it should be surfaced loudly
  to the operator rather than retried.
  """
  @spec next_nonce() :: integer()
  def next_nonce do
    GenServer.call(__MODULE__, :next_nonce)
  end

  @impl GenServer
  def init(_opts) do
    path = dets_path()
    {:ok, _ref} = :dets.open_file(@dets_table, file: String.to_charlist(path), type: :set)
    last = read_last_nonce()
    now = :os.system_time(:millisecond)
    # TODO: emit telemetry event for nonce initialisation once the telemetry
    # hub exists (Phase 2+). This is a meaningful boot event — it records
    # the recovered nonce and whether clock or DETS was the higher bound,
    # which is diagnostic context for EAPI:Invalid nonce investigations.
    initial = max(now, last + 1)
    {:ok, %{last: initial - 1}}
  end

  @impl GenServer
  def handle_call(:next_nonce, _from, %{last: last} = state) do
    nonce = last + 1
    persist(nonce)
    {:reply, nonce, %{state | last: nonce}}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    :dets.close(@dets_table)
  end

  defp read_last_nonce do
    case :dets.lookup(@dets_table, :last_nonce) do
      [{:last_nonce, value}] -> value
      [] -> 0
    end
  end

  defp persist(nonce) do
    :dets.insert(@dets_table, {:last_nonce, nonce})
    :dets.sync(@dets_table)
  end

  defp dets_path do
    Path.expand(
      Application.get_env(:triskele_kraken_client, :nonce_dets_path, @default_dets_path)
    )
  end
end
