defmodule TriskeleCase do
  @moduledoc """
  Base test case for Triskele.

  Provides:
  - Tag-based phase filtering: `@moduletag :phase_3`
  - Common imports and aliases

  Usage:

      defmodule MyTest do
        use TriskeleCase
      end

  Phase tags allow running only tests relevant to a given phase:

      mix test --only phase_1
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import TriskeleCase
    end
  end
end
