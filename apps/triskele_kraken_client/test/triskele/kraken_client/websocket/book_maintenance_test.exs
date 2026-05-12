defmodule Triskele.KrakenClient.WebSocket.BookMaintenanceTest do
  use ExUnit.Case, async: true

  alias Triskele.KrakenClient.WebSocket.BookMaintenance

  @moduletag :phase_1

  # ────────────────────────────────────────────────
  # Fixture from Kraken WS v2 docs
  # https://docs.kraken.com/api/docs/guides/spot-ws-book-v2
  #
  # The worked example in the docs lists 10 asks and 10 bids. We reconstructed
  # each level by parsing the published concatenated checksum string:
  #
  #   asks: 45285210000045286415457195345286615457110945289615456091145290215890660
  #         452918154553491452947445474945296135380000452975994554245299518772827
  #   bids: 452835100000004528341545820154528211000000045281010000000452803154592586
  #         452790799000045277633101034527753000000045277315460273745276615445238
  #
  # Expected CRC32: 3310070434
  # ────────────────────────────────────────────────

  # Verbatim concatenated checksum string published by Kraken (asks + bids).
  # If build_crc_string/2 produces this string, the algorithm is correct
  # regardless of whether the CRC32 value matches — separating fixture errors
  # from algorithm bugs.
  @kraken_docs_checksum_string "45285210000045286415457195345286615457110945289615456091145290215890660" <>
                                 "452918154553491452947445474945296135380000452975994554245299518772827" <>
                                 "452835100000004528341545820154528211000000045281010000000452803154592586" <>
                                 "452790799000045277633101034527753000000045277315460273745276615445238"

  @asks_fixture [
    %{"price" => "45285.2", "qty" => "0.00100000"},
    %{"price" => "45286.4", "qty" => "1.54571953"},
    %{"price" => "45286.6", "qty" => "1.54571109"},
    %{"price" => "45289.6", "qty" => "1.54560911"},
    %{"price" => "45290.2", "qty" => "1.5890660"},
    %{"price" => "45291.8", "qty" => "1.54553491"},
    %{"price" => "45294.7", "qty" => "0.4454749"},
    %{"price" => "45296.1", "qty" => "3.5380000"},
    %{"price" => "45297.5", "qty" => "9.945542"},
    %{"price" => "45299.5", "qty" => "1.8772827"}
  ]

  @bids_fixture [
    %{"price" => "45283.5", "qty" => "1.0000000"},
    %{"price" => "45283.4", "qty" => "1.54582015"},
    %{"price" => "45282.1", "qty" => "1.0000000"},
    %{"price" => "45281.0", "qty" => "1.0000000"},
    %{"price" => "45280.3", "qty" => "1.54592586"},
    %{"price" => "45279.0", "qty" => "0.799000"},
    %{"price" => "45277.6", "qty" => "3.310103"},
    %{"price" => "45277.5", "qty" => "3.0000000"},
    %{"price" => "45277.3", "qty" => "1.54602737"},
    %{"price" => "45276.6", "qty" => "1.5445238"}
  ]

  describe "build_crc_string/2 — Kraken docs fixture" do
    test "matches the published Kraken WS v2 checksum string byte-for-byte" do
      # This test catches fixture transcription errors independently of the CRC32
      # arithmetic. If this passes but the CRC32 test fails, the bug is in
      # :erlang.crc32 (impossible) or the expected CRC constant is wrong.
      # If this fails, the fixture levels above don't match the docs.
      bids = BookMaintenance.parse_levels(@bids_fixture)
      asks = BookMaintenance.parse_levels(@asks_fixture)

      assert BookMaintenance.build_crc_string(bids, asks) == @kraken_docs_checksum_string
    end
  end

  describe "compute_book_crc/2 — Kraken docs fixture" do
    test "produces 3310070434 for the published docs levels" do
      bids = BookMaintenance.parse_levels(@bids_fixture)
      asks = BookMaintenance.parse_levels(@asks_fixture)

      assert BookMaintenance.compute_book_crc(bids, asks) == 3_310_070_434
    end

    test "asks-then-bids ordering: swapping produces a different checksum" do
      bids = BookMaintenance.parse_levels(@bids_fixture)
      asks = BookMaintenance.parse_levels(@asks_fixture)

      # bids_as_asks, asks_as_bids — wrong argument order
      assert BookMaintenance.compute_book_crc(asks, bids) != 3_310_070_434
    end

    test "only top 10 levels are used regardless of book depth" do
      # 11th ask at a worse (higher) price must not change the CRC
      asks_11 = [%{"price" => "46000.0", "qty" => "5.0"} | @asks_fixture]
      bids = BookMaintenance.parse_levels(@bids_fixture)
      asks = BookMaintenance.parse_levels(asks_11)

      assert BookMaintenance.compute_book_crc(bids, asks) == 3_310_070_434
    end

    test "returns :erlang.crc32 of empty string for an empty book" do
      assert BookMaintenance.compute_book_crc(%{}, %{}) == :erlang.crc32("")
    end
  end

  describe "parse_levels/1" do
    test "nil returns empty map" do
      assert BookMaintenance.parse_levels(nil) == %{}
    end

    test "string price/qty preserve trailing zeros for exact CRC match" do
      levels = BookMaintenance.parse_levels([%{"price" => "100.50", "qty" => "0.00100000"}])

      assert Map.has_key?(levels, "100.50")
      assert levels["100.50"].price_crc == "10050"
      assert levels["100.50"].qty_crc == "100000"
    end

    test "float price/qty use Float.to_string (compact, trailing zeros lost)" do
      levels = BookMaintenance.parse_levels([%{"price" => 100.5, "qty" => 1.5}])

      assert Map.has_key?(levels, 100.5)
      assert levels[100.5].price_crc == "1005"
      assert levels[100.5].qty_crc == "15"
    end

    test "integer price/qty formatted without decimal point" do
      levels = BookMaintenance.parse_levels([%{"price" => 100, "qty" => 2}])

      assert Map.has_key?(levels, 100)
      assert levels[100].price_crc == "100"
      assert levels[100].qty_crc == "2"
    end

    test "price Decimal is parsed correctly from string inputs" do
      levels = BookMaintenance.parse_levels([%{"price" => "37500.0", "qty" => "1.25000000"}])
      level = levels["37500.0"]

      assert Decimal.equal?(level.price, Decimal.new("37500.0"))
      assert Decimal.equal?(level.qty, Decimal.new("1.25000000"))
    end

    test "same numeric price in different string formats produces different map keys" do
      # Documents the known behaviour: raw string is the key.
      # Kraken sends consistent representations in practice.
      levels_a = BookMaintenance.parse_levels([%{"price" => "37500.0", "qty" => "1.0"}])
      levels_b = BookMaintenance.parse_levels([%{"price" => "37500", "qty" => "1.0"}])

      refute Map.has_key?(levels_a, "37500")
      refute Map.has_key?(levels_b, "37500.0")
    end
  end

  describe "apply_update/2" do
    test "adds a new bid level" do
      bids = BookMaintenance.parse_levels([%{"price" => "100.0", "qty" => "1.0"}])
      asks = BookMaintenance.parse_levels([%{"price" => "101.0", "qty" => "1.0"}])
      book = %{bids: bids, asks: asks}

      new_bids_levels = [
        %{"price" => "100.0", "qty" => "1.0"},
        %{"price" => "99.0", "qty" => "2.0"}
      ]

      expected_crc =
        BookMaintenance.compute_book_crc(
          BookMaintenance.parse_levels(new_bids_levels),
          asks
        )

      data = %{
        "symbol" => "BTC/USD",
        "bids" => [%{"price" => "99.0", "qty" => "2.0"}],
        "asks" => [],
        "checksum" => expected_crc,
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:ok, updated_book, _book_update} = BookMaintenance.apply_update(book, data)
      assert Map.has_key?(updated_book.bids, "99.0")
      assert Map.has_key?(updated_book.bids, "100.0")
    end

    test "removes a bid level when qty is 0" do
      bids =
        BookMaintenance.parse_levels([
          %{"price" => "100.0", "qty" => "1.0"},
          %{"price" => "99.0", "qty" => "2.0"}
        ])

      asks = BookMaintenance.parse_levels([%{"price" => "101.0", "qty" => "1.0"}])
      book = %{bids: bids, asks: asks}

      remaining_bids = BookMaintenance.parse_levels([%{"price" => "100.0", "qty" => "1.0"}])
      expected_crc = BookMaintenance.compute_book_crc(remaining_bids, asks)

      data = %{
        "symbol" => "BTC/USD",
        "bids" => [%{"price" => "99.0", "qty" => "0"}],
        "asks" => [],
        "checksum" => expected_crc,
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:ok, updated_book, _} = BookMaintenance.apply_update(book, data)
      refute Map.has_key?(updated_book.bids, "99.0")
      assert Map.has_key?(updated_book.bids, "100.0")
    end

    test "returns checksum_mismatch when checksum is wrong" do
      bids = BookMaintenance.parse_levels([%{"price" => "100.0", "qty" => "1.0"}])
      asks = BookMaintenance.parse_levels([%{"price" => "101.0", "qty" => "1.0"}])
      book = %{bids: bids, asks: asks}

      data = %{
        "symbol" => "BTC/USD",
        "bids" => [],
        "asks" => [],
        "checksum" => 0,
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:error, :checksum_mismatch} = BookMaintenance.apply_update(book, data)
    end
  end

  describe "init_from_snapshot/1" do
    test "accepts snapshot when CRC matches" do
      crc =
        BookMaintenance.compute_book_crc(
          BookMaintenance.parse_levels(@bids_fixture),
          BookMaintenance.parse_levels(@asks_fixture)
        )

      data = %{
        "symbol" => "BTC/USD",
        "bids" => @bids_fixture,
        "asks" => @asks_fixture,
        "checksum" => crc,
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:ok, book, order_book} = BookMaintenance.init_from_snapshot(data)
      assert map_size(book.bids) == 10
      assert map_size(book.asks) == 10
      assert order_book.symbol == "BTC/USD"
    end

    test "rejects snapshot with wrong CRC" do
      data = %{
        "symbol" => "BTC/USD",
        "bids" => @bids_fixture,
        "asks" => @asks_fixture,
        "checksum" => 0,
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:error, :checksum_mismatch} = BookMaintenance.init_from_snapshot(data)
    end
  end

  describe "lstrip_zeros edge cases (via parse_levels)" do
    test "0.00100000 strips to 100000, not 1" do
      levels = BookMaintenance.parse_levels([%{"price" => "1.0", "qty" => "0.00100000"}])
      assert levels["1.0"].qty_crc == "100000"
    end

    test "value '0' stays as '0', not empty string" do
      levels = BookMaintenance.parse_levels([%{"price" => "0", "qty" => "0"}])
      assert levels["0"].price_crc == "0"
      assert levels["0"].qty_crc == "0"
    end
  end
end
