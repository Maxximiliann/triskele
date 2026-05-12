# Triskele — Disaster Recovery

This document describes how to restore a fully operational Triskele instance
from a wiped or failed local machine.

## Prerequisites

- Replacement hardware running Ubuntu Server 24.04 LTS
- Access to the password manager entry containing `.env.triskele`
- Access to the Backblaze B2 bucket (credentials in password manager)
- GPG private key available (needed to decrypt encrypted backups)

## Recovery Steps

### 1. Provision the replacement machine

Follow preflight checklist sections D.1–D.4 (hardware, network, asdf toolchain,
Postgres 16, GPG/SSH keys). This sets up the same software environment as
the original machine.

### 2. Clone the repository

```bash
git clone git@github.com:Maxximiliann/triskele.git ~/triskele
cd ~/triskele
```

### 3. Restore secrets

Copy `.env.triskele` from the password manager to `~/.env.triskele`.
Verify it is sourced from `~/.zshrc`:

```bash
grep env.triskele ~/.zshrc
source ~/.env.triskele
echo $DATABASE_URL   # should be non-empty
```

### 4. Restore the Postgres database

```bash
./deploy/scripts/restore_db.sh
```

This script downloads the latest encrypted backup from B2, decrypts it with
GPG, and restores it into the local Postgres instance.

### 5. Restore Mnesia data

```bash
./deploy/scripts/restore_mnesia.sh
```

Restores the Mnesia database (WAL + completed cycle records) from the latest
B2 backup.

### 6. Install dependencies and compile

```bash
mix deps.get && mix compile
```

### 7. Boot and verify kill switch

```bash
mix phx.server
```

Navigate to the dashboard. Confirm the kill switch is **engaged** (red
indicator). The system should start in a paused state (`KILL_SWITCH_ON_BOOT=true`).

**Do not disengage the kill switch until you have verified state reconciliation.**

### 8. Reconcile state with Kraken

```bash
mix triskele.reconcile
```

This compares the local Postgres journal and Mnesia WAL against Kraken's
order history. Any discrepancies are surfaced as warnings requiring manual
review.

Only after a clean reconciliation is the system safe to resume trading.

## Backup Schedule

- Postgres journal: continuous streaming to B2, daily full dump
- Mnesia WAL: hourly snapshot to B2
- Retention: 90 days

## Contact

Operator: Maximilian — Telegram `@M4x1m1l14nn`
