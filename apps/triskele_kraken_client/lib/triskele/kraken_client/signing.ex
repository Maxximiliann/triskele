defmodule Triskele.KrakenClient.Signing do
  @moduledoc "Public API"

  @doc """
  Signs a Kraken private REST request.

  Algorithm (from Kraken's API documentation):
    1. Compute SHA-256 of (nonce_string <> url_encoded_body)
    2. Concatenate: UTF-8 bytes of `path` ++ SHA-256 binary digest
    3. HMAC-SHA-512 the concatenated bytes using Base64-decoded `secret`
    4. Base64-encode the result

  `body` must already be the URL-encoded form body including the nonce
  parameter (e.g. `"nonce=1616492376594&ordertype=limit&..."`).
  `nonce` is the integer nonce value prepended as a plain string before
  hashing — it appears twice in the signing input (once as a bare integer
  string, once URL-encoded inside `body`).

  ## Security note

  Direct callers of this function should be limited to
  `Triskele.KrakenClient.SecretKeeper`. The `secret` parameter contains
  the raw `KRAKEN_API_SECRET`; calling this function from any other process
  causes the secret to enter that process's scope, which defeats the
  isolation model described in Bible §2.1.5.

  Other Kraken API callers should use `SecretKeeper.sign/3` instead,
  which returns `{api_key, signature}` without exposing the secret to
  the caller's process.
  """
  @spec sign(path :: String.t(), nonce :: integer(), body :: String.t(), secret :: String.t()) ::
          String.t()
  def sign(path, nonce, body, secret)
      when is_binary(path) and is_integer(nonce) and is_binary(body) and is_binary(secret) do
    message = Integer.to_string(nonce) <> body
    sha256 = :crypto.hash(:sha256, message)
    decoded_secret = Base.decode64!(secret)
    hmac_input = path <> sha256
    mac = :crypto.mac(:hmac, :sha512, decoded_secret, hmac_input)
    Base.encode64(mac)
  end
end
