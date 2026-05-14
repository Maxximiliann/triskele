defmodule Triskele.KrakenClient.WebSocket.Connection do
  @moduledoc """
  Shared Mint.WebSocket plumbing used by WebSocket.Public and WebSocket.Private.

  ## Connection lifecycle

  `connect/1` sends the HTTP/1.1 Upgrade request and returns `{:ok, {conn, ref}}`
  without waiting for the 101 response. Because `Mint.HTTP.connect/4` is called in
  the calling process (a GenServer), the calling process owns the socket. Mint sets
  the socket to `active: :once` internally, so the 101 Switching Protocols response
  arrives as `{:tcp, socket, data}` in the GenServer's mailbox after `connect/1`
  returns.

  The GenServer accumulates `:status` and `:headers` responses via `stream/2`, then
  calls `finalize_upgrade/4` once the `:done` response is received.
  """

  @spec connect(String.t()) ::
          {:ok, {Mint.HTTP.t(), Mint.Types.request_ref()}} | {:error, term()}
  def connect(url) do
    uri = URI.parse(url)
    {http_scheme, ws_scheme} = url_schemes(uri.scheme)
    host = uri.host
    port = uri.port || default_port(http_scheme)
    path = uri.path || "/"

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, host, port, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []) do
      {:ok, {conn, ref}}
    end
  end

  @spec finalize_upgrade(
          Mint.HTTP.t(),
          Mint.Types.request_ref(),
          integer(),
          [{String.t(), String.t()}]
        ) :: {:ok, {Mint.HTTP.t(), Mint.WebSocket.t()}} | {:error, term()}
  def finalize_upgrade(conn, ref, status, headers) do
    case Mint.WebSocket.new(conn, ref, status, headers) do
      {:ok, conn, websocket} -> {:ok, {conn, websocket}}
      {:error, _conn, reason} -> {:error, reason}
    end
  end

  @spec stream(Mint.HTTP.t(), term()) ::
          {:ok, Mint.HTTP.t(), list()} | {:error, Mint.HTTP.t(), term(), list()} | :unknown
  def stream(conn, message), do: Mint.WebSocket.stream(conn, message)

  @spec decode(Mint.WebSocket.t(), binary()) ::
          {:ok, Mint.WebSocket.t(), list(Mint.WebSocket.frame())}
          | {:error, Mint.WebSocket.t(), term()}
  def decode(websocket, data), do: Mint.WebSocket.decode(websocket, data)

  @spec send_frame(
          Mint.HTTP.t(),
          Mint.WebSocket.t(),
          Mint.Types.request_ref(),
          Mint.WebSocket.frame()
        ) :: {:ok, {Mint.HTTP.t(), Mint.WebSocket.t()}} | {:error, term()}
  def send_frame(conn, websocket, ref, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      {:ok, {conn, websocket}}
    else
      {:error, _struct, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_text(Mint.HTTP.t(), Mint.WebSocket.t(), Mint.Types.request_ref(), String.t()) ::
          {:ok, {Mint.HTTP.t(), Mint.WebSocket.t()}} | {:error, term()}
  def send_text(conn, websocket, ref, text) do
    send_frame(conn, websocket, ref, {:text, text})
  end

  @spec close(Mint.HTTP.t(), Mint.WebSocket.t() | nil, Mint.Types.request_ref() | nil) :: :ok
  def close(conn, websocket, ref) do
    if websocket && ref do
      case Mint.WebSocket.encode(websocket, :close) do
        {:ok, _ws, data} -> Mint.WebSocket.stream_request_body(conn, ref, data)
        _ -> :ok
      end
    end

    Mint.HTTP.close(conn)
    :ok
  rescue
    _ -> :ok
  end

  defp url_schemes("wss"), do: {:https, :wss}
  defp url_schemes("ws"), do: {:http, :ws}

  defp default_port(:https), do: 443
  defp default_port(:http), do: 80
end
