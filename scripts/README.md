# scripts/

Operator-run scripts not invoked by `mix` tasks or the OTP
application. Each script documents its purpose, invocation, and
environment requirements inline.

## phase1_live_smoke.exs

Five-check end-to-end validation of the Kraken supervision tree
against live Kraken (`wss://ws.kraken.com/v2`,
`wss://ws-auth.kraken.com/v2`, and `api.kraken.com`). Used as the
live-environment gate before Phase 1 PR creation.

**Checks:**

- `[a]` Supervisor tree health — confirms 8 children are alive
  under `Triskele.KrakenClient.Supervisor` (Finch, SecretKeeper,
  Nonce, RateLimit, Auth, Phoenix.PubSub, Public, Private).
- `[b]` Auth token presence — `Auth.current_token/0` returns a
  non-empty binary. The token's bytes are never logged; only
  presence and length.
- `[c]` Public book subscribe (BTC/USD) — subscribes to the
  `book:BTC/USD:{snapshot,update,reset}` PubSub topics, calls
  `Public.subscribe_book("BTC/USD")`, and waits up to 10s for the
  first book frame. CRC mismatch (`:book_reset`) on the first
  frame is treated as failure.
- `[d]` Private executions subscribe — subscribes to the
  `executions` PubSub topic, calls `Private.subscribe_executions/0`,
  and waits up to 10s for a snapshot (or initial update if the
  snapshot was empty).
- `[e]` Clean shutdown — unsubscribes both channels,
  `Supervisor.stop(Triskele.KrakenClient.Supervisor, :normal)`,
  asserts the original child pids exit. The AppSupervisor may
  restart the tree with fresh pids; the check verifies the
  original-pid death only.

**Invocation:**

    iex -S mix run scripts/phase1_live_smoke.exs

Run from the umbrella root.

**Environment requirements:**

- `KRAKEN_API_KEY` and `KRAKEN_API_SECRET` exported in the
  invoking shell. The script reads them via the application
  config / `SecretKeeper` boot path; the script itself does NOT
  log token bytes. If a token-shaped string surfaces in Logger
  or telemetry output during the smoke, that is a leak.
- Network access to `api.kraken.com`, `ws.kraken.com`, and
  `ws-auth.kraken.com`.
- Live Kraken account credentials with sufficient permissions
  for the subscribed channels (read-only is sufficient — the
  smoke does not place orders).

**Expected output:** A summary block with one line per check
labeled `a`/`b`/`c`/`d`/`e` and an `OVERALL: PASS` / `FAIL` line.
Each check renders as `PASS — <reason>` / `FAIL — <reason>` /
`SKIP — <reason>`.

**Maintenance:** Checked in to make the Phase 1 validation gate
reproducible. Update alongside any Phase 2+ change that alters
the WebSocket or REST contract, the supervision tree child
count, or the PubSub topic shapes.
