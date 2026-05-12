defmodule Triskele.Util.Time do
  @moduledoc """
  Time utilities — UTC internal, Denver display.

  Internal state and records are always UTC. The display layer converts to
  `America/Denver` for the operator. Tax dates use Denver-local date per
  Project Bible §2.2.3.

  Use `monotonic_us/0` for latency measurement. Use `utc_now/0` for events
  that need wall-clock context. Never compare monotonic to system time.
  """

  @display_zone "America/Denver"

  @spec utc_now() :: DateTime.t()
  def utc_now, do: DateTime.utc_now()

  @spec monotonic_us() :: integer()
  def monotonic_us, do: :erlang.monotonic_time(:microsecond)

  @spec to_display(DateTime.t()) :: DateTime.t()
  def to_display(%DateTime{} = dt) do
    DateTime.shift_zone!(dt, @display_zone)
  end

  @spec to_local_date(DateTime.t()) :: Date.t()
  def to_local_date(%DateTime{} = dt) do
    dt
    |> to_display()
    |> DateTime.to_date()
  end

  @spec format_display(DateTime.t()) :: String.t()
  def format_display(%DateTime{} = dt) do
    dt
    |> to_display()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S %Z")
  end
end
