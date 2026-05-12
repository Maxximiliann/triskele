defmodule Triskele.Common do
  @moduledoc """
  Shared infrastructure utilities for the Triskele umbrella.

  This app is a pure library: no business logic, no domain types,
  no supervision tree. It is a leaf node in the dependency graph —
  every other Triskele app may depend on it; it depends on none of them.

  Namespaces provided:
  - `Triskele.Util.*` — cross-cutting utilities (time, etc.)
  - `Triskele.Types.*` — shared type definitions (added as needed)
  """
end
