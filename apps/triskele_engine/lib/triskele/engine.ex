defmodule Triskele.Engine do
  @moduledoc """
  Cycle detection, scoring, and dispatch.

  Continuously scans order books for three-asset cycles whose net-of-fees-and-slippage
  expected USD profit exceeds the configured edge threshold, then dispatches
  candidates to the execution subsystem.

  Implemented in Phase 2.
  """
end
