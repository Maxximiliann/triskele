defmodule Triskele.KrakenClient.RateLimit do
  @moduledoc "Public API"

  use GenServer

  @pro_capacity 180
  @pro_decay_per_ms 3.75 / 1000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Acquires `cost` tokens from the rate-limit bucket, blocking until available.

  Pass `wait: false` to return `{:error, :rate_limited}` immediately instead
  of blocking when the bucket is insufficient.
  """
  @spec acquire(cost :: pos_integer(), opts :: keyword()) :: :ok | {:error, :rate_limited}
  def acquire(cost, opts \\ []) do
    wait = Keyword.get(opts, :wait, true)
    GenServer.call(__MODULE__, {:acquire, cost, wait}, :infinity)
  end

  @impl GenServer
  def init(opts) do
    capacity = Keyword.get(opts, :capacity, @pro_capacity)
    decay_per_ms = Keyword.get(opts, :decay_per_ms, @pro_decay_per_ms)

    state = %{
      tokens: capacity * 1.0,
      capacity: capacity * 1.0,
      decay_per_ms: decay_per_ms,
      last_refill_at: monotonic_ms()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:acquire, cost, wait}, from, state) do
    state = refill(state)

    if state.tokens >= cost do
      {:reply, :ok, %{state | tokens: state.tokens - cost}}
    else
      if wait do
        wait_ms = ceil((cost - state.tokens) / state.decay_per_ms)
        Process.send_after(self(), {:retry, cost, from}, wait_ms)
        {:noreply, state}
      else
        {:reply, {:error, :rate_limited}, state}
      end
    end
  end

  @impl GenServer
  def handle_info({:retry, cost, from}, state) do
    state = refill(state)

    if state.tokens >= cost do
      GenServer.reply(from, :ok)
      {:noreply, %{state | tokens: state.tokens - cost}}
    else
      wait_ms = ceil((cost - state.tokens) / state.decay_per_ms)
      Process.send_after(self(), {:retry, cost, from}, wait_ms)
      {:noreply, state}
    end
  end

  defp refill(
         %{tokens: tokens, capacity: capacity, decay_per_ms: decay, last_refill_at: last} = state
       ) do
    now = monotonic_ms()
    elapsed = now - last
    new_tokens = min(capacity, tokens + elapsed * decay)
    %{state | tokens: new_tokens, last_refill_at: now}
  end

  defp monotonic_ms do
    :erlang.monotonic_time(:millisecond)
  end
end
