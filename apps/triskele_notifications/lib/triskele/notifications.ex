defmodule Triskele.Notifications do
  @moduledoc """
  Operator alert delivery via Telegram bot, web push, and email fallback.

  Fires alerts for cycle completions, kill switch state changes, daily loss
  budget warnings, and system errors. All delivery is async and non-blocking
  with respect to the trading hot path.

  Implemented in Phase 6.
  """
end
