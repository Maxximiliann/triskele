defmodule Triskele.Telemetry do
  @moduledoc """
  Metrics aggregation, distributed tracing, and structured logging.

  All meaningful events in the hot path are emitted as `:telemetry` events.
  This subsystem aggregates them into Prometheus metrics, JSON logs, and
  OpenTelemetry spans. Direct `Logger` calls from the hot path are forbidden.

  Implemented in Phase 1+.
  """
end
