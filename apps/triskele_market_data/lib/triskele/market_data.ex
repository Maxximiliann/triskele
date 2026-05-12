defmodule Triskele.MarketData do
  @moduledoc """
  Order book ingestion and maintenance.

  Subscribes to Kraken's WebSocket feed, maintains per-pair order books in ETS,
  and exposes a read interface for the engine's cycle scanner.

  Implemented in Phase 1.
  """
end
