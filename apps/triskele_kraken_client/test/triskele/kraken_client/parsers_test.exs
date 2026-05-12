defmodule Triskele.KrakenClient.ParsersTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Triskele.KrakenClient.Parsers

  @moduletag :phase_1

  describe "decimal_from_term/1" do
    test "returns nil for nil" do
      assert Parsers.decimal_from_term(nil) == nil
    end

    test "parses binary strings exactly" do
      assert Parsers.decimal_from_term("0.0001") == Decimal.new("0.0001")
      assert Parsers.decimal_from_term("37500.00") == Decimal.new("37500.00")
      assert Parsers.decimal_from_term("1.25") == Decimal.new("1.25")
    end

    test "parses integers exactly" do
      assert Parsers.decimal_from_term(0) == Decimal.new(0)
      assert Parsers.decimal_from_term(100) == Decimal.new(100)
    end

    test "round-trips floats through string representation (no IEEE 754 precision artifact)" do
      assert Parsers.decimal_from_term(0.0001) == Decimal.new(Float.to_string(0.0001))
      assert Parsers.decimal_from_term(0.1) == Decimal.new(Float.to_string(0.1))
      assert Parsers.decimal_from_term(1.5) == Decimal.new(Float.to_string(1.5))
    end

    test "float result does not carry full IEEE 754 binary representation" do
      result = Parsers.decimal_from_term(0.0001)
      str = Decimal.to_string(result)

      refute String.length(str) > 20,
             "expected compact decimal, got #{inspect(str)} — possible Decimal.from_float/1 regression"
    end

    test "precision holds for 100 random small floats" do
      # Seed for reproducibility across runs
      :rand.seed(:exsss, {42, 0, 0})

      for _ <- 1..100 do
        f = :rand.uniform() / 1.0e3
        result = Parsers.decimal_from_term(f)
        expected = Decimal.new(Float.to_string(f))

        assert Decimal.equal?(result, expected),
               "decimal_from_term(#{f}) != Decimal.new(#{Float.to_string(f)})"
      end
    end
  end

  describe "datetime_from_unix/1" do
    test "converts epoch 0 to 1970-01-01T00:00:00Z" do
      assert Parsers.datetime_from_unix(0) == ~U[1970-01-01 00:00:00Z]
    end

    test "converts a known Unix timestamp" do
      assert Parsers.datetime_from_unix(1_616_492_376) ==
               DateTime.from_unix!(1_616_492_376, :second)
    end
  end

  describe "datetime_from_iso8601/1" do
    test "parses valid ISO 8601 string" do
      assert {:ok, dt} = Parsers.datetime_from_iso8601("2024-01-15T12:00:00.000000Z")
      assert dt.year == 2024
      assert dt.month == 1
      assert dt.day == 15
      assert dt.hour == 12
    end

    test "returns error for invalid string" do
      assert {:error, _} = Parsers.datetime_from_iso8601("not-a-date")
    end
  end

  describe "datetime_from_iso8601!/1" do
    test "raises for invalid string" do
      assert_raise MatchError, fn -> Parsers.datetime_from_iso8601!("bad") end
    end
  end
end
