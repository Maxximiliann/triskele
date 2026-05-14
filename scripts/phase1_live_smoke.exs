# ============================================================================
# Phase 1 live smoke test — Kraken supervision tree
# ============================================================================
#
# ONE-SHOT operator-driven artifact. NOT part of `mix test`.
#
# Exercises the production supervision tree against LIVE Kraken
# (wss://ws.kraken.com/v2 + wss://ws-auth.kraken.com/v2 + api.kraken.com).
# Requires KRAKEN_API_KEY and KRAKEN_API_SECRET in the environment.
#
# Run from the umbrella root:
#
#     iex -S mix run scripts/phase1_live_smoke.exs
#
# Application boot starts the full supervision tree because dev env defaults
# `:start_supervision_tree` to true. After the script's checks complete,
# control returns to the iex prompt for manual inspection if needed.
#
# Token discipline: this script NEVER logs the token value or any prefix/
# suffix. Auth-check output reports only `auth_token: present (length=N)`.
# If you see a token-shaped string anywhere in Logger or telemetry output
# during the smoke, that's a leak — surface it.
#
# ============================================================================

alias Triskele.KrakenClient.WebSocket.Auth
alias Triskele.KrakenClient.WebSocket.Private
alias Triskele.KrakenClient.WebSocket.Public

defmodule Phase1LiveSmoke do
  @moduledoc false

  def run do
    Process.flag(:trap_exit, true)
    IO.puts("==========================================")
    IO.puts("Phase 1 live smoke — Kraken supervision tree")
    IO.puts("==========================================")

    # Allow init/1 + Mint upgrade + Auth REST + initial subscribe time
    # to settle. Public/Private fire `send(self(), :connect)` in init and
    # the WebSocket upgrade + first Kraken frame takes ~1-3 s.
    IO.puts("\nWaiting 3s for supervision tree + initial WS connections...")
    Process.sleep(3_000)

    a = check_tree_health()
    b = check_auth_token()
    c = check_public_subscribe_tick()
    d = check_private_executions_snapshot()
    e = clean_shutdown()

    IO.puts("\n==========================================")
    IO.puts("SUMMARY")
    IO.puts("==========================================")
    IO.puts("  a. tree health:           #{format(a)}")
    IO.puts("  b. auth token:            #{format(b)}")
    IO.puts("  c. public book tick:      #{format(c)}")
    IO.puts("  d. private executions:    #{format(d)}")
    IO.puts("  e. clean shutdown:        #{format(e)}")
    IO.puts("==========================================")

    overall = if Enum.all?([a, b, c, d, e], &match?({:ok, _}, &1)), do: "PASS", else: "FAIL"
    IO.puts("\nOVERALL: #{overall}")
    IO.puts("(See details above for any FAIL or SKIP entries.)")
  end

  defp format({:ok, msg}), do: "PASS — #{msg}"
  defp format({:fail, msg}), do: "FAIL — #{msg}"
  defp format({:skip, msg}), do: "SKIP — #{msg}"

  # --------------------------------------------------------------------------

  defp check_tree_health do
    IO.puts("\n[a] tree health — Supervisor.which_children/1")

    try do
      children = Supervisor.which_children(Triskele.KrakenClient.Supervisor)

      Enum.each(children, fn {id, pid, type, _mods} ->
        alive? = is_pid(pid) and Process.alive?(pid)
        IO.puts("    #{inspect(id)} [#{type}] pid=#{inspect(pid)} alive=#{alive?}")
      end)

      all_alive =
        Enum.all?(children, fn {_id, pid, _type, _mods} ->
          is_pid(pid) and Process.alive?(pid)
        end)

      count = length(children)

      cond do
        count != 8 -> {:fail, "expected 8 children, got #{count}"}
        not all_alive -> {:fail, "one or more children not alive"}
        true -> {:ok, "8/8 children alive"}
      end
    rescue
      e -> {:fail, "Supervisor.which_children/1 raised: #{inspect(e)}"}
    catch
      kind, value -> {:fail, "raised #{kind}: #{inspect(value)}"}
    end
  end

  # --------------------------------------------------------------------------

  defp check_auth_token do
    IO.puts("\n[b] auth token — Auth.current_token/0 (presence-only)")

    try do
      token = Auth.current_token()

      cond do
        is_binary(token) ->
          IO.puts("    auth_token: present (length=#{byte_size(token)})")
          {:ok, "token present, #{byte_size(token)} bytes"}

        is_nil(token) ->
          {:fail, "current_token returned nil"}

        true ->
          {:fail, "current_token returned non-binary: #{inspect(token)}"}
      end
    rescue
      e -> {:fail, "current_token raised: #{inspect(e)}"}
    catch
      kind, _value -> {:fail, "current_token raised #{kind}"}
    end
  end

  # --------------------------------------------------------------------------

  defp check_public_subscribe_tick do
    IO.puts("\n[c] public book subscribe BTC/USD — wait up to 10s for first frame")

    try do
      Phoenix.PubSub.subscribe(Triskele.PubSub, "book:BTC/USD:snapshot")
      Phoenix.PubSub.subscribe(Triskele.PubSub, "book:BTC/USD:update")
      Phoenix.PubSub.subscribe(Triskele.PubSub, "book:BTC/USD:reset")

      :ok = Public.subscribe_book("BTC/USD")

      receive do
        {:book_snapshot, _book, _ts} ->
          IO.puts("    received: book_snapshot")
          {:ok, "snapshot received"}

        {:book_update, _update, _ts} ->
          IO.puts("    received: book_update")
          {:ok, "update received"}

        {:book_reset, _sym} ->
          {:fail, "received :book_reset (CRC mismatch on first frame — investigate)"}
      after
        10_000 -> {:fail, "no book message within 10s"}
      end
    rescue
      e -> {:fail, "raised: #{inspect(e)}"}
    catch
      kind, value -> {:fail, "raised #{kind}: #{inspect(value)}"}
    end
  end

  # --------------------------------------------------------------------------

  defp check_private_executions_snapshot do
    IO.puts("\n[d] private executions subscribe — wait up to 10s for snapshot")

    try do
      Phoenix.PubSub.subscribe(Triskele.PubSub, "executions")

      :ok = Private.subscribe_executions()

      receive do
        {:executions, %{type: :snapshot, data: data, sequence: seq}} ->
          IO.puts("    received: executions snapshot, #{length(data)} items, sequence=#{seq}")
          {:ok, "snapshot received (#{length(data)} items)"}

        {:executions, %{type: :update, data: _data, sequence: seq}} ->
          IO.puts("    received: executions update before snapshot, sequence=#{seq}")
          {:ok, "update received (snapshot may have been empty initial state)"}
      after
        10_000 -> {:fail, "no executions message within 10s"}
      end
    rescue
      e -> {:fail, "raised: #{inspect(e)}"}
    catch
      kind, value -> {:fail, "raised #{kind}: #{inspect(value)}"}
    end
  end

  # --------------------------------------------------------------------------

  defp clean_shutdown do
    IO.puts("\n[e] clean shutdown — capture pids, then Supervisor.stop")

    try do
      _ = Public.unsubscribe_book("BTC/USD")
      _ = Private.unsubscribe_executions()
      Process.sleep(300)

      # Capture child pids BEFORE stop. AppSupervisor (parent) will likely
      # restart Triskele.KrakenClient.Supervisor with fresh pids; we assert
      # the ORIGINAL pids exit cleanly. New pids from restart are not part
      # of this test.
      original_pids =
        Supervisor.which_children(Triskele.KrakenClient.Supervisor)
        |> Enum.map(fn {_id, pid, _type, _mods} -> pid end)
        |> Enum.reject(&(not is_pid(&1)))

      :ok = Supervisor.stop(Triskele.KrakenClient.Supervisor, :normal)
      Process.sleep(500)

      all_dead = Enum.all?(original_pids, fn pid -> not Process.alive?(pid) end)

      cond do
        not all_dead ->
          dead_count = Enum.count(original_pids, fn pid -> not Process.alive?(pid) end)
          {:fail, "#{dead_count}/#{length(original_pids)} original children dead after stop"}

        true ->
          {:ok,
           "all #{length(original_pids)} original children dead (AppSupervisor may restart fresh)"}
      end
    rescue
      e -> {:fail, "shutdown raised: #{inspect(e)}"}
    catch
      kind, value -> {:fail, "shutdown raised #{kind}: #{inspect(value)}"}
    end
  end
end

Phase1LiveSmoke.run()
