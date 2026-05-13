# Dialyzer ignore list.
#
# Each entry is a tuple of {file_pattern, warning_type, line},
# {file_pattern, warning_type}, {file_pattern}, or a regex applied to the
# short-description output. See dialyxir's README:
#   https://github.com/jeremyjh/dialyxir#elixir-term-format
#
# Maintenance: dialyxir reports "Unnecessary Skips" when a line-pinned
# entry no longer matches a warning. If that happens, re-run
# `mix dialyzer`, update the line numbers below, and remove any entries
# whose underlying warnings have actually been fixed.

[
  # ─────────────────────────────────────────────────────────────────────
  # Mint opaque-type leaks in WebSocket.Connection wrapper functions.
  #
  # `Mint.HTTP1.t/0`, `Mint.HTTP2.t/0`, `Mint.UnsafeProxy.t/0`, and
  # `Mint.WebSocket.t/0` are all declared `@opaque` upstream.
  # `Triskele.KrakenClient.WebSocket.Connection` is a thin pass-through
  # wrapper around `Mint.WebSocket` — it never constructs or inspects
  # these structs, only delegates. Dialyzer's opaque-type rules flag this
  # pattern even though it is the documented usage of the Mint API.
  #
  # See DEVIATIONS_LOG.md entry DEV-008 for rationale and lifecycle.
  # Upstream context: elixir-mint/mint_web_socket#30.
  # ─────────────────────────────────────────────────────────────────────
  {"lib/triskele/kraken_client/websocket/connection.ex", :call_with_opaque, 28},
  {"lib/triskele/kraken_client/websocket/connection.ex", :invalid_contract, 33},
  {"lib/triskele/kraken_client/websocket/connection.ex", :invalid_contract, 46}
]
