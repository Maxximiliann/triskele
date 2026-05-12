defmodule Triskele.KrakenClient.RateLimitTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Triskele.KrakenClient.RateLimit

  @moduletag :phase_1

  defp start_bucket(capacity, decay_per_ms) do
    start_supervised!({RateLimit, capacity: capacity, decay_per_ms: decay_per_ms})
  end

  describe "acquire/2 with wait: false" do
    test "succeeds immediately when bucket has sufficient tokens" do
      start_bucket(10, 1.0)
      assert :ok = RateLimit.acquire(5, wait: false)
    end

    test "returns rate_limited immediately when bucket is insufficient" do
      start_bucket(3, 0.001)
      assert :ok = RateLimit.acquire(3, wait: false)
      assert {:error, :rate_limited} = RateLimit.acquire(1, wait: false)
    end

    test "allows acquisition up to full capacity" do
      start_bucket(10, 0.001)
      assert :ok = RateLimit.acquire(10, wait: false)
    end

    test "rejects when cost exceeds remaining tokens" do
      start_bucket(5, 0.001)
      assert :ok = RateLimit.acquire(4, wait: false)
      assert {:error, :rate_limited} = RateLimit.acquire(2, wait: false)
    end

    test "bucket refills over time" do
      start_bucket(10, 10.0)
      assert :ok = RateLimit.acquire(10, wait: false)
      assert {:error, :rate_limited} = RateLimit.acquire(5, wait: false)
      Process.sleep(1_000)
      assert :ok = RateLimit.acquire(5, wait: false)
    end
  end

  describe "acquire/2 with wait: true (default)" do
    test "blocks until tokens are available then returns :ok" do
      start_bucket(5, 10.0)
      assert :ok = RateLimit.acquire(5, wait: false)

      task = Task.async(fn -> RateLimit.acquire(5) end)
      assert :ok = Task.await(task, 2_000)
    end

    test "multiple waiters are each satisfied in turn" do
      start_bucket(2, 10.0)
      assert :ok = RateLimit.acquire(2, wait: false)

      tasks = Enum.map(1..3, fn _ -> Task.async(fn -> RateLimit.acquire(2) end) end)
      results = Enum.map(tasks, &Task.await(&1, 5_000))
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "bucket math" do
    test "token count does not exceed capacity after refill" do
      start_bucket(10, 100.0)
      Process.sleep(200)
      assert :ok = RateLimit.acquire(10, wait: false)
      assert {:error, :rate_limited} = RateLimit.acquire(1, wait: false)
    end
  end
end
