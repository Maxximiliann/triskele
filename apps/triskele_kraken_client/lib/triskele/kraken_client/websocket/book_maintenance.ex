defmodule Triskele.KrakenClient.WebSocket.BookMaintenance do
  @moduledoc """
  Pure functions for maintaining a local order book with CRC32 validation.

  ## CRC32 algorithm (Kraken WS v2 spec)

  The checksum string is formed by concatenating the top-10 ask levels (price
  ascending) followed by the top-10 bid levels (price descending). For each
  level, the price and qty strings are processed by removing the decimal point
  and stripping leading zeros, then concatenated: `price_crc <> qty_crc`.

  Example: price `"45285.2"`, qty `"0.00100000"` →
  `"452852"` + `"100000"` = `"452852100000"`.

  The CRC string is passed to `:erlang.crc32/1` to produce the checksum.

  ## Map key

  The raw price STRING from the feed is used as the map key. Using a parsed
  `Decimal` as the key is unsafe: `Decimal.new("37500.0")` and
  `Decimal.new("37500")` are structurally different Decimals and hash to
  different keys even though they represent the same price. Raw strings are
  immune to this provided Kraken sends the same price in the same string format
  across snapshot and update messages (which it does in practice).

  ## String precision (resolved)

  Kraken WS v2 actually sends `price` and `qty` in the book channel as JSON
  numbers, not strings (verified by `:erlang.trace` capture against live
  `wss://ws.kraken.com/v2`). The production decoders at `Public.handle_frame/2`
  and `Private.handle_frame/2` use `Jason.decode(json, floats: :decimals)` so
  numbers arrive in this module as `%Decimal{}` structs carrying the wire-format
  digit sequence exactly (Decimal's coefficient + exponent preserve the
  original precision).

  `crc_str/1` has three clauses:

  - **`%Decimal{}`** — the production path. Uses `Decimal.to_string(d, :normal)`
    to render the wire-format digits, then strips the decimal point and leading
    zeros per Kraken's spec.
  - **`binary`** — retained for test-fixture compatibility. Existing fixtures
    construct level maps directly (bypassing Jason) with string price/qty;
    those continue to work. Fixture regeneration to use `%Decimal{}` shapes
    matching the live wire is a follow-up.
  - **`float`** — defense-in-depth fallback, unreachable by design in
    production now that the decode option is in place. Retained intentionally.
  """

  alias Triskele.KrakenClient.Types.BookUpdate
  alias Triskele.KrakenClient.Types.OrderBook

  @zero_qty Decimal.new(0)

  @type level :: %{
          price: Decimal.t(),
          qty: Decimal.t(),
          price_crc: String.t(),
          qty_crc: String.t()
        }
  @type book_side :: %{String.t() => level()}
  @type book :: %{bids: book_side(), asks: book_side()}

  @doc """
  Initialises local book state from a snapshot WebSocket message.

  Returns `{:ok, book, %OrderBook{}}` when the computed CRC32 matches
  `data["checksum"]`, or `{:error, :checksum_mismatch}` otherwise.
  """
  @spec init_from_snapshot(map()) :: {:ok, book(), OrderBook.t()} | {:error, :checksum_mismatch}
  def init_from_snapshot(data) do
    bids = parse_levels(data["bids"])
    asks = parse_levels(data["asks"])
    expected = data["checksum"]
    computed = compute_book_crc(bids, asks)

    if computed == expected do
      {:ok, %{bids: bids, asks: asks}, OrderBook.from_ws(data)}
    else
      {:error, :checksum_mismatch}
    end
  end

  @doc """
  Applies a book-update delta and validates the resulting CRC32.

  Returns `{:ok, updated_book, %BookUpdate{}}` or `{:error, :checksum_mismatch}`.
  """
  @spec apply_update(book(), map()) ::
          {:ok, book(), BookUpdate.t()} | {:error, :checksum_mismatch}
  def apply_update(%{bids: bids, asks: asks}, data) do
    bid_deltas = parse_levels(data["bids"])
    ask_deltas = parse_levels(data["asks"])
    expected = data["checksum"]

    new_bids = apply_deltas(bids, bid_deltas)
    new_asks = apply_deltas(asks, ask_deltas)
    computed = compute_book_crc(new_bids, new_asks)

    if computed == expected do
      {:ok, %{bids: new_bids, asks: new_asks}, BookUpdate.from_ws(data)}
    else
      {:error, :checksum_mismatch}
    end
  end

  @doc """
  Builds the CRC32 input string per Kraken WS v2 spec.

  Exported for testing — production callers should use `compute_book_crc/2`.
  Having the intermediate string in tests allows byte-for-byte comparison
  against Kraken's published docs example, separating fixture errors from
  algorithm errors.
  """
  @spec build_crc_string(book_side(), book_side()) :: String.t()
  def build_crc_string(bids, asks) do
    top_10_crc(asks, :asc) <> top_10_crc(bids, :desc)
  end

  @doc """
  Computes the Kraken WS v2 CRC32 checksum for the given book sides.

  Exported so tests can build an expected checksum independently without
  going through a full snapshot or update message.
  """
  @spec compute_book_crc(book_side(), book_side()) :: non_neg_integer()
  def compute_book_crc(bids, asks) do
    bids
    |> build_crc_string(asks)
    |> :erlang.crc32()
  end

  @doc false
  @spec parse_levels(nil | list()) :: book_side()
  def parse_levels(nil), do: %{}

  def parse_levels(levels) when is_list(levels) do
    Map.new(levels, fn level ->
      raw_price = level["price"]
      raw_qty = level["qty"]

      {raw_price,
       %{
         price: to_decimal(raw_price),
         qty: to_decimal(raw_qty),
         price_crc: crc_str(raw_price),
         qty_crc: crc_str(raw_qty)
       }}
    end)
  end

  # ────────────────────────────────────────────────
  # Delta application
  # ────────────────────────────────────────────────

  @spec apply_deltas(book_side(), book_side()) :: book_side()
  defp apply_deltas(book_side, deltas) do
    Enum.reduce(deltas, book_side, fn {price_str, %{qty: qty} = entry}, acc ->
      if Decimal.equal?(qty, @zero_qty) do
        Map.delete(acc, price_str)
      else
        Map.put(acc, price_str, entry)
      end
    end)
  end

  # ────────────────────────────────────────────────
  # Helpers
  # ────────────────────────────────────────────────

  defp top_10_crc(levels, :asc) do
    levels
    |> Enum.sort(fn {_, %{price: a}}, {_, %{price: b}} -> Decimal.compare(a, b) == :lt end)
    |> Enum.take(10)
    |> Enum.map_join("", fn {_, %{price_crc: p, qty_crc: q}} -> p <> q end)
  end

  defp top_10_crc(levels, :desc) do
    levels
    |> Enum.sort(fn {_, %{price: a}}, {_, %{price: b}} -> Decimal.compare(a, b) == :gt end)
    |> Enum.take(10)
    |> Enum.map_join("", fn {_, %{price_crc: p, qty_crc: q}} -> p <> q end)
  end

  defp to_decimal(%Decimal{} = d), do: d

  defp to_decimal(v) when is_binary(v), do: Decimal.new(v)

  defp to_decimal(v) when is_float(v) do
    v
    |> Float.to_string()
    |> Decimal.new()
  end

  defp to_decimal(v) when is_integer(v), do: Decimal.new(v)

  defp crc_str(v) when is_binary(v) do
    v
    |> String.replace(".", "")
    |> lstrip_zeros()
  end

  defp crc_str(%Decimal{} = d) do
    d
    |> Decimal.to_string(:normal)
    |> String.replace(".", "")
    |> String.trim_leading("0")
  end

  defp crc_str(v) when is_float(v) do
    v
    |> Float.to_string()
    |> String.replace(".", "")
    |> lstrip_zeros()
  end

  defp crc_str(v) when is_integer(v) do
    v
    |> Integer.to_string()
    |> lstrip_zeros()
  end

  defp lstrip_zeros(""), do: "0"
  defp lstrip_zeros(<<"0", rest::binary>>), do: lstrip_zeros(rest)
  defp lstrip_zeros(str), do: str
end
