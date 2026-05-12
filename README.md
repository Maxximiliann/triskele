# Triskele

> **Pre-paper-trading. Not for live capital.**

Triskele is a fault-tolerant, high-throughput intra-exchange triangular arbitrage
trading system targeting the Kraken cryptocurrency exchange. It is written in
Elixir/OTP and exposes a Phoenix LiveView dashboard for operation by a single
authenticated user.

See [`docs/architecture.md`](docs/architecture.md) for the system overview and
[`docs/PROJECT_BIBLE.md`](docs/PROJECT_BIBLE.md) for the authoritative design
reference.

---

## Setup

### Prerequisites

- [asdf](https://asdf-vm.com/) with the versions pinned in `.tool-versions`
- PostgreSQL 16 running locally
- Environment variables from `.env.example` populated in `~/.env.triskele`

### Install

```bash
asdf install
mix setup          # fetches deps
mix ecto.setup     # creates and migrates databases (Phase 4+)
```

### Run

```bash
mix phx.server     # starts the Phoenix endpoint (Phase 6+)
```

### Test

```bash
mix test           # runs all tests
mix test.all       # runs with coverage report
mix quality        # format check + credo + dialyzer
```

---

## Operator Runbook

See [`docs/runbook.md`](docs/runbook.md).

---

## Disaster Recovery

See [`docs/disaster_recovery.md`](docs/disaster_recovery.md).

---

## Status

This system is under active development. It is **not yet safe for live capital**.
The five reliability gates defined in the Project Bible must all pass before
any real funds are deployed.

Current phase: **Phase 0 — Bootstrap**
