defmodule Triskele.Persistence do
  @moduledoc """
  Mnesia WAL, Postgres trade journal, and audit log.

  The Mnesia WAL provides crash-safe leg state persistence across BEAM restarts.
  The Postgres journal is the long-term record for P&L analysis and tax export.

  Implemented in Phase 3 (WAL) and Phase 4 (Postgres journal).
  """
end
