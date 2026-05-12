defmodule Triskele.KrakenClient.NonceTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Triskele.KrakenClient.Nonce

  @moduletag :phase_1

  setup do
    dets_path =
      Path.join(System.tmp_dir!(), "nonce_test_#{System.unique_integer([:positive])}.dets")

    Application.put_env(:triskele_kraken_client, :nonce_dets_path, dets_path)

    {:ok, pid} = start_supervised({Nonce, []})

    on_exit(fn ->
      Application.delete_env(:triskele_kraken_client, :nonce_dets_path)
      File.rm(dets_path)
    end)

    {:ok, pid: pid}
  end

  describe "next_nonce/0" do
    test "returns an integer" do
      assert is_integer(Nonce.next_nonce())
    end

    test "is strictly increasing on sequential calls" do
      n1 = Nonce.next_nonce()
      n2 = Nonce.next_nonce()
      n3 = Nonce.next_nonce()
      assert n2 > n1
      assert n3 > n2
    end

    test "initial value is at least current system time in milliseconds" do
      before = :os.system_time(:millisecond)
      nonce = Nonce.next_nonce()
      assert nonce >= before
    end

    test "is monotonically increasing under concurrent access" do
      concurrency = 50

      nonces =
        1..concurrency
        |> Task.async_stream(fn _ -> Nonce.next_nonce() end,
          max_concurrency: concurrency,
          ordered: false
        )
        |> Enum.map(fn {:ok, n} -> n end)
        |> Enum.sort()

      assert length(nonces) == concurrency

      nonces
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert b > a, "nonce #{b} is not greater than preceding nonce #{a}"
      end)
    end

    test "no duplicate nonces under concurrent access" do
      nonces =
        1..100
        |> Task.async_stream(fn _ -> Nonce.next_nonce() end, max_concurrency: 100, ordered: false)
        |> Enum.map(fn {:ok, n} -> n end)

      assert length(nonces) == length(Enum.uniq(nonces))
    end
  end

  describe "restart recovery" do
    test "restores monotonicity from DETS across GenServer restarts" do
      nonce_before = Nonce.next_nonce()
      stop_supervised!(Nonce)

      {:ok, _} = start_supervised({Nonce, []})
      nonce_after = Nonce.next_nonce()

      assert nonce_after > nonce_before
    end
  end
end
