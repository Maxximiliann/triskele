defmodule Triskele.Tax do
  @moduledoc """
  FIFO cost basis tracking and TurboTax-compatible Form 8949 export.

  Tax events use Denver-local date per Project Bible §2.2.3: a trade at
  11:30pm Denver on December 31 is a current-year trade even though it is
  already January 1 UTC.

  Implemented in Phase 6.
  """
end
