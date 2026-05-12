defmodule Triskele.KrakenClient.SigningTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Triskele.KrakenClient.Signing

  @moduletag :phase_1

  # Fixture sourced from Kraken's official REST API authentication guide:
  # https://docs.kraken.com/api/docs/guides/spot-rest-auth
  # Verified against our implementation on 2026-05-12.
  @kraken_docs_path "/0/private/AddOrder"
  @kraken_docs_nonce 1_616_492_376_594
  @kraken_docs_body "nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25"
  @kraken_docs_secret "kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg=="
  @kraken_docs_expected "4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ=="

  describe "sign/4" do
    test "produces the expected signature for the Kraken docs fixture" do
      result =
        Signing.sign(
          @kraken_docs_path,
          @kraken_docs_nonce,
          @kraken_docs_body,
          @kraken_docs_secret
        )

      assert result == @kraken_docs_expected
    end

    test "returns a base64-encoded binary" do
      result =
        Signing.sign(
          @kraken_docs_path,
          @kraken_docs_nonce,
          @kraken_docs_body,
          @kraken_docs_secret
        )

      assert is_binary(result)
      assert {:ok, decoded} = Base.decode64(result)
      assert byte_size(decoded) == 64
    end

    test "is deterministic — same inputs always produce the same signature" do
      sig1 =
        Signing.sign(
          @kraken_docs_path,
          @kraken_docs_nonce,
          @kraken_docs_body,
          @kraken_docs_secret
        )

      sig2 =
        Signing.sign(
          @kraken_docs_path,
          @kraken_docs_nonce,
          @kraken_docs_body,
          @kraken_docs_secret
        )

      assert sig1 == sig2
    end

    test "different nonces produce different signatures" do
      sig1 = Signing.sign(@kraken_docs_path, 1_000_000, @kraken_docs_body, @kraken_docs_secret)
      sig2 = Signing.sign(@kraken_docs_path, 1_000_001, @kraken_docs_body, @kraken_docs_secret)
      refute sig1 == sig2
    end

    test "different paths produce different signatures" do
      sig1 =
        Signing.sign(
          "/0/private/AddOrder",
          @kraken_docs_nonce,
          @kraken_docs_body,
          @kraken_docs_secret
        )

      sig2 =
        Signing.sign(
          "/0/private/CancelOrder",
          @kraken_docs_nonce,
          @kraken_docs_body,
          @kraken_docs_secret
        )

      refute sig1 == sig2
    end

    test "different secrets produce different signatures" do
      other_secret = Base.encode64("different_secret_key_padded_here!!")

      sig1 =
        Signing.sign(
          @kraken_docs_path,
          @kraken_docs_nonce,
          @kraken_docs_body,
          @kraken_docs_secret
        )

      sig2 = Signing.sign(@kraken_docs_path, @kraken_docs_nonce, @kraken_docs_body, other_secret)
      refute sig1 == sig2
    end
  end
end
