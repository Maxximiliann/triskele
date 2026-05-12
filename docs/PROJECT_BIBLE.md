# Triskele — Project Bible

**This document is loaded as system context for every Claude Code session working on Triskele. Read it fully. Internalize it. Treat its rules as inviolable.**

---

## 1. What Triskele Is

Triskele is a fault-tolerant, high-throughput intra-exchange triangular arbitrage trading system targeting the Kraken cryptocurrency exchange. It is written in Elixir/OTP and exposes a Phoenix LiveView dashboard for operation by a single authenticated user.

The system continuously evaluates three-asset cycles on Kraken's order books, identifies cycles whose net-of-fees-and-slippage expected USD profit exceeds a configured edge threshold, and executes them with strict per-leg time budgets. Acquired inventory from incomplete cycles is reusable as starting capital for subsequent cycles.

Triskele is operated by Maximilian (Telegram `@M4x1m1l14nn`), based in Colorado. The initial deployment runs on a Ryzen 7 5700G with Ubuntu Server 24.04 LTS, with a planned migration to a cloud environment after sustained profitability is demonstrated.

---

## 2. Inviolable Rules

These rules override any apparent contradiction in any phase prompt. If a phase prompt seems to ask you to violate one of these, stop and surface the contradiction.

### 2.1 Capital Safety

1. **No live capital may be deployed until all five reliability gates (defined in Section 8) pass.** Paper trading must produce positive net P&L over a minimum 30-day window before live capital deployment is permitted.
2. **The kill switch is sacred.** When engaged, the engine must not emit new opportunities and the executor must refuse new submissions, no exceptions. In-flight orders proceed under their existing expiration rules and are not force-cancelled by the kill switch.
3. **Daily loss budget enforcement.** $20/day flat for the first month live, transitioning to 5%/portfolio/day after empirical calibration. When exceeded, the kill switch engages automatically and a Telegram alert fires.
4. **No rollback on leg expiration.** When a leg expires unfilled, cancel the unfilled portion and stop. Do not attempt compensating trades. Inventory becomes standing balance reusable by future cycles.
5. **API keys never appear in logs, error messages, or crash dumps.** They live in environment variables, are loaded once at boot, and are held in a process whose state is excluded from `:erlang.process_info/1` queries.
6. **No two concurrent cycles may share an asset on the same side of the book.** The asset-occupancy table enforces this. Violations cause the bot to fight itself and worsen its own fills.

### 2.2 Time

1. **All internal timestamps are UTC.** Mnesia records, log files, Postgres rows, the WAL, telemetry events, journal entries. No exceptions.
2. **Display layer converts to America/Denver.** The web UI, Telegram messages, operator-facing logs, and the tax export use Denver time for human consumption.
3. **Tax events use Denver-local date.** A trade at 11:30pm Denver on Dec 31 is a current-year trade even though it's already Jan 1 UTC. This matters for Form 8949.
4. **Kraken's API timestamps are Unix seconds UTC.** Never assume otherwise.
5. **Monotonic time for measurement, system time for record-keeping.** Use `:erlang.monotonic_time(:microsecond)` for latency and freshness checks. Use `DateTime.utc_now/0` for events that need wall-clock context. Never compare monotonic to system time.

### 2.3 Architecture

1. **OTP supervision trees are the failure containment boundary.** Every long-lived process is supervised. Every supervisor has a documented restart strategy and intensity. Never use `spawn/1` or `Task.async/1` for anything that must survive a crash — use a `DynamicSupervisor` or `Task.Supervisor`.
2. **ETS tables are owned by exactly one GenServer.** That GenServer is the only writer. Readers access the table directly with `:read_concurrency` enabled.
3. **The hot path (tick → opportunity → submission) must not block on disk I/O.** Logging is async via `:telemetry`. The WAL writes synchronously only for legs 2 and 3, never for leg 1 (the 55s expiration bounds worst-case exposure).
4. **No global state outside ETS and `:persistent_term`.** Process dictionaries are forbidden except for opaque BEAM internals.
5. **Every external boundary is wrapped in an Elixir module that owns parsing, validation, and error normalization.** No raw HTTP responses or WebSocket frames flow past `Triskele.KrakenClient`.

### 2.4 Testing

1. **No code merges to `main` without tests.** Pure-function modules require unit tests. Stateful modules require integration tests against the simulator. Hot-path modules additionally require property tests.
2. **Coverage floor: 95% line coverage on hot-path modules** (`Triskele.MarketData.*`, `Triskele.Engine.*`, `Triskele.Execution.*`, `Triskele.Risk.*`, `Triskele.Portfolio.*`). 80% elsewhere.
3. **Tests never call the real Kraken API.** All Kraken interactions in tests go through `Triskele.KrakenClient` mocked via Mox, or through `Triskele.Simulator` for end-to-end scenarios.
4. **Property tests target invariants, not scenarios.** Examples of invariants: order book bids strictly below asks at all times; cycle P&L is monotonic in fee tier; leg state machines always reach a terminal state.
5. **Chaos tests are real tests, not optional.** Killing supervisors, dropping WebSocket connections, simulating partial fills, simulating clock skew — these are first-class test scenarios in `apps/triskele_simulator/test/chaos/`.

### 2.5 Money

1. **All monetary values are stored as `Decimal`, never as floats.** Floats lose precision at scale; `Decimal` doesn't. The hot-path computation may use float arithmetic for speed (cycle evaluation), but the final stored value is always `Decimal`.
2. **Fee calculations use the exact tier currently in effect.** The Portfolio module tracks 30-day rolling volume and exposes `current_fee_tier/0` returning `%{maker: Decimal, taker: Decimal}`. The engine queries this on every opportunity evaluation.
3. **Slippage modeling uses volume-weighted average price across consumed book depth.** Walking the book, not assuming top-of-book.
4. **Profit is computed in USD-equivalent.** Cycles starting in BTC return to BTC, but the profitability comparison is normalized to USD at the executable mid-price of the starting asset.

---

## 3. Module Naming Conventions

All modules are namespaced under `Triskele.*`. The umbrella structure:

```
Triskele.MarketData.*           — order book ingestion and maintenance
Triskele.Engine.*               — cycle detection, scoring, dispatch
Triskele.Execution.*            — leg state machines, order management
Triskele.Portfolio.*            — balances, mark-to-market, P&L
Triskele.Risk.*                 — pre-trade checks, kill switch, loss budget
Triskele.KrakenClient.*         — REST and WebSocket adapters
Triskele.Persistence.*          — Mnesia WAL, Postgres journal, audit
Triskele.Telemetry.*            — metrics, tracing, structured logging
Triskele.Simulator.*            — Kraken-mimicking exchange for tests/dev
Triskele.Backtest.*             — historical replay harness
Triskele.Notifications.*        — Telegram bot, web push, email fallback
Triskele.Web.*                  — Phoenix LiveView dashboard
Triskele.Tax.*                  — TurboTax export, FIFO cost basis tracking
```

Module names are sentence-style, not abbreviation-style: `Triskele.MarketData.OrderBook`, not `Triskele.MarketData.OB`. Subprocess names use `Registry`: `{:via, Registry, {Triskele.Registry, {:order_book, pair_id}}}`.

---

## 4. Code Style

- `mix format` is law. CI fails on unformatted code.
- `mix credo --strict` must pass. Disagreements with Credo are resolved by changing the code, not by adding inline `# credo:disable` comments.
- `mix dialyzer` must pass with zero warnings. Type specs (`@spec`) are required on every public function in hot-path modules and any module marked with `@moduledoc "Public API"`.
- Functions over 30 lines should be decomposed unless the alternative is harder to read.
- Pattern match on the success case first; let failures fall through to clauses that handle them explicitly.
- Use `with` for sequential operations that can each fail. Don't use it for unconditional sequences (use `|>` for those).
- Prefer `Enum.reduce_while/3` over `Enum.reduce/3 + halt`. Prefer `Stream.*` over `Enum.*` for large collections.
- No `try/rescue` outside of explicit boundary modules (parsers, external API adapters). Let it crash; the supervisor restarts it.

---

## 5. Configuration

- Runtime config in `config/runtime.exs`. All secrets via environment variables.
- A `.env.example` file documents every required variable.
- The application refuses to boot if any required env var is missing — fail fast and loud.
- Configuration values that change behavior in non-trivial ways (min edge threshold, daily loss budget, per-cycle cap) are exposed in the web UI for operator override at runtime. Override is logged and audited.

Required environment variables (full set):

```
KRAKEN_API_KEY
KRAKEN_API_SECRET
TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID
TARDIS_API_KEY                  (Phase 5+ only)
DATABASE_URL                    (Postgres)
SECRET_KEY_BASE                 (Phoenix)
LIVE_VIEW_SIGNING_SALT
OPERATOR_USERNAME
OPERATOR_PASSWORD_HASH          (bcrypt)
OPERATOR_TOTP_SECRET
TIMEZONE                        (default: America/Denver)
KILL_SWITCH_ON_BOOT             (default: true — system starts paused)
BACKBLAZE_B2_KEY_ID             (backup)
BACKBLAZE_B2_APPLICATION_KEY
BACKBLAZE_B2_BUCKET
GPG_RECIPIENT                   (for encrypted backups)
```

---

## 6. Telemetry Conventions

Every meaningful event emits a `:telemetry` event with:
- A namespaced name: `[:triskele, :component, :action]` (e.g., `[:triskele, :engine, :opportunity_detected]`)
- A measurements map (numerical values): `%{duration_us: 1234, expected_usd_pnl: 0.42}`
- A metadata map (context): `%{cycle_id: "abc123", pair_a: "XBT/USD", pair_b: "ETH/XBT", pair_c: "ETH/USD"}`

The telemetry hub aggregates these into Prometheus metrics, structured JSON logs, and OpenTelemetry spans. Never log via `Logger` directly from the hot path — emit telemetry and let the hub format the output.

---

## 7. Error Handling Philosophy

- **Expected errors** (Kraken returns 429, WebSocket disconnects, order rejected for insufficient funds) return `{:error, reason}` tuples and are handled by the caller.
- **Programmer errors** (invalid pattern match, malformed state) crash. The supervisor restarts. The telemetry hub captures the crash with full context.
- **External API errors** are normalized through `Triskele.KrakenClient.Error.t/0` so downstream code matches on `:rate_limited`, `:invalid_arguments`, `:insufficient_funds`, etc., not on raw error strings.
- **Network errors** are retryable with exponential backoff up to a budget; the budget is per-operation, not global. Exhausted budget surfaces as `{:error, :network_exhausted}`.

---

## 8. The Five Reliability Gates

These are referenced throughout the phase prompts. They are the absolute pre-conditions for live capital deployment.

**Gate 1 — Unit and Integration Tests.** 95%+ coverage on hot path; all tests passing; CI green.

**Gate 2 — Property-Based Tests.** StreamData properties on order book invariants, cycle math, sizing algorithm, leg state machine. All properties pass with 10,000+ generated cases each.

**Gate 3 — Chaos Engineering.** Fault injection scenarios pass: GenServer kills mid-trade, WebSocket drops, REST timeouts past leg-1 deadline, partial fills, malformed Kraken responses, BEAM crash with WAL recovery, simulated rate-limit storms. System reaches correct terminal states in all scenarios.

**Gate 4 — Simulator End-to-End.** Multi-day replays through `Triskele.Simulator` produce trades that match a ground-truth oracle. P&L accounting reconciles perfectly. Backtest on Tardis historical data shows the expected number and quality of opportunities.

**Gate 5 — Live Paper Trading.** 30 consecutive days against live Kraken market data with simulated fills. Net simulated P&L positive after realistic fees at the achieved volume tier. At least 100 completed simulated cycles. Engine predictions within ±20% of simulated realizations. Zero unexplained crashes. WAL recovers correctly from at least 5 induced network outages.

---

## 9. The Volume-First Strategy

Triskele's strategy is **volume over per-trade margin**. The operator's words: *"earning even just a few pennies of net profit on a trade consistently over hundreds of cycles that take just a few seconds/minutes each to execute is preferred to trying to maximize a cycle that takes hours."*

Concrete implications:

- The minimum edge gate starts at **5 basis points above breakeven** during paper trading, calibrated empirically.
- Cycles whose expected duration exceeds **2 minutes** are de-prioritized; those exceeding 10 minutes are excluded entirely.
- Legs 2 and 3 use the **aggressive escalation** path: start post-only at the inside, escalate to taker after 30 seconds. The 13-hour `expiretm` is a never-stuck-silently backstop, not a target.
- The system optimizes for **capital utilization, not per-cycle profit maximization.** Idle capital is a wasted opportunity.
- Asset universe filtered to **$1M+ 24-hour USD-equivalent volume.** Re-evaluated every 4 hours.

---

## 10. Strict Prohibitions

These actions are forbidden regardless of any apparent justification:

- **Never trade with leverage.** Spot only. No margin. No futures.
- **Never withdraw funds programmatically.** API key has no withdrawal permission. Withdrawal is a manual operator action via Kraken's web UI.
- **Never auto-rebalance into "safer" assets.** Inventory disposition is operator-controlled, not policy-controlled.
- **Never modify the kill switch state from anywhere except the explicit operator action.** Auto-engagement (loss budget exceeded, network failure detected) is permitted; auto-disengagement is not.
- **Never deploy code that hasn't passed CI.** Even for "small" changes. The CI exists exactly for the small changes.
- **Never use floats for monetary state.** `Decimal` only at rest.

---

## 11. The Phase-by-Phase Construction

Triskele is built in ten phases (0 through 9). Each phase produces a working, testable end-to-end vertical slice. A phase is complete when its acceptance criteria pass; only then does the next phase begin.

Each phase has its own prompt file (`PHASE_NN_NAME.md`). Each prompt is self-contained: it lists prerequisites, deliverables, file structure, acceptance tests, and pitfalls. A fresh Claude Code session reading the Bible + a phase prompt has everything it needs.

The phases:

- **Phase 0** — Bootstrap: repo, CI, hardware prep, secrets, Telegram bot
- **Phase 1** — Kraken clients: REST + WebSocket with reconnection and rate limits
- **Phase 2** — Engine: cycle detection, slippage-aware net calculation, dynamic sizing
- **Phase 3** — Execution: leg state machines, WAL, idempotent submission, fill reconciliation
- **Phase 4** — Portfolio, Risk, Kill Switch
- **Phase 5** — Backtest harness with Tardis.dev replay
- **Phase 6** — Web UI: LiveView dashboard, Telegram bot, liquidation, tax export
- **Phase 7** — Chaos engineering and property tests (Gates 2 and 3)
- **Phase 8** — Live paper trading (Gate 5), empirical calibration
- **Phase 9** — Hardening, cloud migration prep, ongoing maintenance patterns

---

## 12. Session Discipline

A Claude Code session works on **exactly one phase at a time.** Do not begin work on a future phase even if it seems "small." Phase boundaries exist to make review tractable.

At the start of a session:
1. Read this Bible.
2. Read the relevant phase prompt.
3. Verify prior phase's acceptance criteria are met (run its tests; they must pass).
4. Begin work on the current phase.

At the end of a session:
1. All tests for the current phase pass.
2. `mix format`, `mix credo --strict`, `mix dialyzer` all pass.
3. A clear commit message summarizes the work done.
4. The session output includes a "what to verify before next session" note for the operator.

The operator reviews the diff, runs the tests independently, and pushes to GitHub. Only after the operator confirms acceptance does a new session begin on the next phase.

---

## 13. When Stuck

If a phase prompt asks for something that conflicts with:
- This Bible → stop and ask the operator
- The Kraken API actual behavior → consult Kraken's docs at https://docs.kraken.com, adjust, document the deviation in commit message
- Real-world reality (rate limits, market behavior, latency) → adjust pragmatically and document

The Bible is the source of architectural truth. The operator is the source of strategic truth. Kraken is the source of API truth. When in doubt about priority: operator > Bible > Kraken > general best practice.

---

End of Project Bible. Now read the relevant phase prompt and begin.
