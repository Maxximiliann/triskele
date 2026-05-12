defmodule Triskele.Execution do
  @moduledoc """
  Leg state machines, order management, and WAL-backed idempotent submission.

  Manages the three-leg lifecycle for each cycle: submission, fill reconciliation,
  timeout escalation, and terminal state recording.

  Implemented in Phase 3.
  """
end
