defmodule Triskele.KrakenClient.ErrorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Triskele.KrakenClient.Error

  @moduletag :phase_1

  describe "from_kraken/1 with a string" do
    test "classifies EAPI:Rate limit exceeded as :rate_limited and retryable" do
      err = Error.from_kraken("EAPI:Rate limit exceeded")
      assert err.kind == :rate_limited
      assert err.retryable == true
      assert err.message == "EAPI:Rate limit exceeded"
    end

    test "classifies EAPI:Invalid nonce as :nonce_invalid and not retryable" do
      err = Error.from_kraken("EAPI:Invalid nonce")
      assert err.kind == :nonce_invalid
      assert err.retryable == false
    end

    test "classifies EAPI:Invalid key as :invalid_arguments and not retryable" do
      err = Error.from_kraken("EAPI:Invalid key")
      assert err.kind == :invalid_arguments
      assert err.retryable == false
    end

    test "classifies EAPI:Invalid signature as :invalid_arguments and not retryable" do
      err = Error.from_kraken("EAPI:Invalid signature")
      assert err.kind == :invalid_arguments
      assert err.retryable == false
    end

    test "classifies EGeneral:Invalid arguments as :invalid_arguments and not retryable" do
      err = Error.from_kraken("EGeneral:Invalid arguments")
      assert err.kind == :invalid_arguments
      assert err.retryable == false
    end

    test "classifies EGeneral:Internal error as :server_error and retryable" do
      err = Error.from_kraken("EGeneral:Internal error")
      assert err.kind == :server_error
      assert err.retryable == true
    end

    test "classifies EService:Unavailable as :server_error and retryable" do
      err = Error.from_kraken("EService:Unavailable")
      assert err.kind == :server_error
      assert err.retryable == true
    end

    test "classifies EService:Busy as :server_error and retryable" do
      err = Error.from_kraken("EService:Busy")
      assert err.kind == :server_error
      assert err.retryable == true
    end

    test "classifies EOrder:Insufficient funds as :insufficient_funds and not retryable" do
      err = Error.from_kraken("EOrder:Insufficient funds")
      assert err.kind == :insufficient_funds
      assert err.retryable == false
    end

    test "classifies unknown strings as :unknown and not retryable" do
      err = Error.from_kraken("EOrder:Something new we never saw before")
      assert err.kind == :unknown
      assert err.retryable == false
    end

    test "preserves the raw string" do
      raw = "EAPI:Rate limit exceeded"
      err = Error.from_kraken(raw)
      assert err.raw == raw
    end
  end

  describe "from_kraken/1 with a list" do
    test "classifies based on the first error string" do
      err = Error.from_kraken(["EAPI:Rate limit exceeded", "EGeneral:Internal error"])
      assert err.kind == :rate_limited
    end

    test "preserves the full error list as raw" do
      errors = ["EAPI:Rate limit exceeded", "EGeneral:Internal error"]
      err = Error.from_kraken(errors)
      assert err.raw == errors
    end
  end

  describe "from_mint/1" do
    test "classifies timeout as :network_timeout and retryable" do
      err = Error.from_mint(%Mint.TransportError{reason: :timeout})
      assert err.kind == :network_timeout
      assert err.retryable == true
    end

    test "classifies connection refused as :network_refused and retryable" do
      err = Error.from_mint(%Mint.TransportError{reason: :econnrefused})
      assert err.kind == :network_refused
      assert err.retryable == true
    end

    test "classifies other Mint transport errors as :network_timeout and retryable" do
      err = Error.from_mint(%Mint.TransportError{reason: :closed})
      assert err.kind == :network_timeout
      assert err.retryable == true
    end

    test "classifies unknown terms as :unknown and not retryable" do
      err = Error.from_mint(:something_unexpected)
      assert err.kind == :unknown
      assert err.retryable == false
    end
  end

  describe "from_http_status/2" do
    test "5xx is :server_error and retryable" do
      err = Error.from_http_status(500, "Internal Server Error")
      assert err.kind == :server_error
      assert err.retryable == true
    end

    test "503 is :server_error and retryable" do
      err = Error.from_http_status(503, "Service Unavailable")
      assert err.kind == :server_error
      assert err.retryable == true
    end

    test "4xx with parseable Kraken error list defers to from_kraken classification" do
      body = Jason.encode!(%{"error" => ["EAPI:Rate limit exceeded"]})
      err = Error.from_http_status(429, body)
      assert err.kind == :rate_limited
      assert err.retryable == true
    end

    test "4xx with Kraken nonce error defers to from_kraken classification" do
      body = Jason.encode!(%{"error" => ["EAPI:Invalid nonce"]})
      err = Error.from_http_status(400, body)
      assert err.kind == :nonce_invalid
      assert err.retryable == false
    end

    test "4xx with non-Kraken body is :invalid_arguments and not retryable" do
      err = Error.from_http_status(404, "Not Found")
      assert err.kind == :invalid_arguments
      assert err.retryable == false
    end

    test "4xx with empty Kraken error list is :invalid_arguments" do
      body = Jason.encode!(%{"error" => []})
      err = Error.from_http_status(400, body)
      assert err.kind == :invalid_arguments
      assert err.retryable == false
    end

    test "preserves {status, body} in raw for all cases" do
      err = Error.from_http_status(500, "oops")
      assert err.raw == {500, "oops"}

      body = Jason.encode!(%{"error" => ["EAPI:Invalid nonce"]})
      err2 = Error.from_http_status(400, body)
      assert {400, ^body} = err2.raw
    end

    test "unexpected status code (e.g. 301) is :unknown and not retryable" do
      err = Error.from_http_status(301, "Moved Permanently")
      assert err.kind == :unknown
      assert err.retryable == false
    end
  end
end
