defmodule Triskele.KrakenClient.Error do
  @moduledoc "Public API"

  @type kind ::
          :rate_limited
          | :nonce_invalid
          | :insufficient_funds
          | :invalid_arguments
          | :network_timeout
          | :network_refused
          | :server_error
          | :unknown

  @enforce_keys [:kind, :message, :raw, :retryable]
  defstruct [:kind, :message, :raw, :retryable]

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          raw: term(),
          retryable: boolean()
        }

  @spec from_kraken(String.t() | [String.t()]) :: t()
  def from_kraken(error_string) when is_binary(error_string) do
    {kind, retryable} = classify(error_string)
    %__MODULE__{kind: kind, message: error_string, raw: error_string, retryable: retryable}
  end

  def from_kraken([first | _] = errors) when is_list(errors) do
    err = from_kraken(first)
    %{err | raw: errors}
  end

  @spec from_mint(term()) :: t()
  def from_mint(%Mint.TransportError{reason: :timeout}) do
    %__MODULE__{
      kind: :network_timeout,
      message: "connection timed out",
      raw: :timeout,
      retryable: true
    }
  end

  def from_mint(%Mint.TransportError{reason: :econnrefused}) do
    %__MODULE__{
      kind: :network_refused,
      message: "connection refused",
      raw: :econnrefused,
      retryable: true
    }
  end

  def from_mint(%Mint.TransportError{} = err) do
    %__MODULE__{kind: :network_timeout, message: inspect(err), raw: err, retryable: true}
  end

  def from_mint(reason) do
    %__MODULE__{kind: :unknown, message: inspect(reason), raw: reason, retryable: false}
  end

  @spec from_http_status(status :: non_neg_integer(), body :: binary()) :: t()
  def from_http_status(status, body) when status >= 500 do
    %__MODULE__{
      kind: :server_error,
      message: "HTTP #{status}",
      raw: {status, body},
      retryable: true
    }
  end

  def from_http_status(status, body) when status >= 400 do
    case Jason.decode(body) do
      {:ok, %{"error" => [_ | _] = errors}} ->
        err = from_kraken(errors)
        %{err | raw: {status, body}}

      _ ->
        %__MODULE__{
          kind: :invalid_arguments,
          message: "HTTP #{status}",
          raw: {status, body},
          retryable: false
        }
    end
  end

  def from_http_status(status, body) do
    %__MODULE__{
      kind: :unknown,
      message: "HTTP #{status}",
      raw: {status, body},
      retryable: false
    }
  end

  defp classify("EAPI:Rate limit exceeded" <> _), do: {:rate_limited, true}
  defp classify("EAPI:Invalid nonce" <> _), do: {:nonce_invalid, false}
  defp classify("EAPI:Invalid key" <> _), do: {:invalid_arguments, false}
  defp classify("EAPI:Invalid signature" <> _), do: {:invalid_arguments, false}
  defp classify("EGeneral:Invalid arguments" <> _), do: {:invalid_arguments, false}
  defp classify("EGeneral:Internal error" <> _), do: {:server_error, true}
  defp classify("EService:Unavailable" <> _), do: {:server_error, true}
  defp classify("EService:Busy" <> _), do: {:server_error, true}
  defp classify("EOrder:Insufficient funds" <> _), do: {:insufficient_funds, false}
  defp classify(_), do: {:unknown, false}
end
