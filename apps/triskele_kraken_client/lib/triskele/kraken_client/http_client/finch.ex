defmodule Triskele.KrakenClient.HTTPClient.Finch do
  @moduledoc false

  @behaviour Triskele.KrakenClient.HTTPClient

  @pool Triskele.KrakenClient.Finch

  @impl Triskele.KrakenClient.HTTPClient
  def get(url, headers) do
    request = Finch.build(:get, url, headers)

    case Finch.request(request, @pool) do
      {:ok, %Finch.Response{status: status, body: response_body}} -> {:ok, status, response_body}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Triskele.KrakenClient.HTTPClient
  def post(url, headers, body) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, @pool) do
      {:ok, %Finch.Response{status: status, body: response_body}} -> {:ok, status, response_body}
      {:error, reason} -> {:error, reason}
    end
  end
end
