defmodule Triskele.Risk do
  @moduledoc """
  Pre-trade checks, kill switch, and daily loss budget enforcement.

  The kill switch is the sacred control: when engaged, no new opportunities
  are emitted and no new submissions are accepted. In-flight orders proceed
  under their existing expiration rules.

  Implemented in Phase 4.
  """
end
