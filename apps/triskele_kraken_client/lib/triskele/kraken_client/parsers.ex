defmodule Triskele.KrakenClient.Parsers do
  @moduledoc "Public API"

  @spec decimal_from_term(nil | binary() | integer() | float()) :: Decimal.t() | nil
  def decimal_from_term(nil), do: nil
  def decimal_from_term(v) when is_binary(v), do: Decimal.new(v)
  def decimal_from_term(v) when is_integer(v), do: Decimal.new(v)

  def decimal_from_term(v) when is_float(v) do
    v
    |> Float.to_string()
    |> Decimal.new()
  end

  @spec datetime_from_unix(integer()) :: DateTime.t()
  def datetime_from_unix(unix_seconds) when is_integer(unix_seconds) do
    DateTime.from_unix!(unix_seconds, :second)
  end

  @spec datetime_from_iso8601(String.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def datetime_from_iso8601(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec datetime_from_iso8601!(String.t()) :: DateTime.t()
  def datetime_from_iso8601!(str) when is_binary(str) do
    {:ok, dt, _offset} = DateTime.from_iso8601(str)
    dt
  end
end
