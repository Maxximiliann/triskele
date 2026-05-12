# Triskele — Architecture Overview

> Authoritative reference: `docs/PROJECT_BIBLE.md`

## What Triskele Does

Triskele is a fault-tolerant intra-exchange triangular arbitrage system for the Kraken cryptocurrency exchange. It continuously evaluates three-asset cycles on live order books, identifies cycles with positive expected USD profit net of fees and slippage, and executes them with strict per-leg time budgets.

## High-Level Component Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Operator Browser                                                           │
│      │  Phoenix LiveView (triskele_web)                                     │
│      └─────────────────────────────────────────────────┐                   │
│                                                         │                   │
│  ┌──────────────────────────────────────────────────────▼─────────────────┐ │
│  │  Triskele OTP Application                                              │ │
│  │                                                                        │ │
│  │  triskele_market_data   ←── Kraken WebSocket feed (via kraken_client)  │ │
│  │       │  Order books (ETS, :read_concurrency)                          │ │
│  │       ▼                                                                │ │
│  │  triskele_engine        ─── Cycle scanner, scoring, dispatch           │ │
│  │       │  Opportunity events (via :telemetry)                           │ │
│  │       ▼                                                                │ │
│  │  triskele_execution     ─── Leg state machines, WAL, order mgmt        │ │
│  │       │  REST + WebSocket (via kraken_client)                          │ │
│  │       ▼                                                                │ │
│  │  triskele_portfolio     ─── Balances, mark-to-market, P&L              │ │
│  │  triskele_risk          ─── Kill switch, daily loss budget             │ │
│  │  triskele_persistence   ─── Mnesia WAL, Postgres journal               │ │
│  │  triskele_telemetry     ─── Metrics, tracing, structured logs          │ │
│  │  triskele_notifications ─── Telegram, web push                         │ │
│  │  triskele_simulator     ─── Mock exchange for tests/dev                │ │
│  │  triskele_backtest      ─── Historical replay (Tardis.dev)             │ │
│  │  triskele_tax           ─── FIFO cost basis, Form 8949 export          │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Elixir/OTP umbrella | Fault isolation per subsystem; supervisor trees as failure boundary |
| ETS for order books | Microsecond read latency without GenServer bottleneck |
| Mnesia WAL for legs | Survives BEAM crash between leg 1 fill and leg 2 submission |
| Postgres for journal | Long-term audit, tax export, P&L analysis |
| `Decimal` for money | Float precision loss unacceptable at scale |
| Kill switch default ON | System starts paused; operator explicitly enables trading |

## Data Flow — Opportunity Lifecycle

1. Kraken WebSocket tick → `MarketData.OrderBook` (ETS update)
2. `Engine.Scanner` reads order books → evaluates all cycles
3. Cycle passes edge threshold → `Engine.Dispatcher` checks asset occupancy
4. Submission dispatched → `Execution.LegStateMachine` (leg 1)
5. Leg 1 fills → leg 2 submitted → leg 3 submitted
6. Cycle complete → `Portfolio` updated → `Persistence.Journal` written
7. `Telemetry` emits all events → Prometheus + structured log

## Time Handling

- **All internal state**: UTC (`DateTime.utc_now/0`, Unix seconds)
- **Display layer**: `America/Denver` via `Triskele.Util.Time.to_display/1`
- **Tax dates**: Denver-local (a 11:30pm Denver trade on Dec 31 is current-year)
- **Latency measurement**: `:erlang.monotonic_time(:microsecond)` only

## Build Phases

See `docs/PROJECT_BIBLE.md` §11 for the ten-phase construction plan.
Current status: Phase 0 (bootstrap).
