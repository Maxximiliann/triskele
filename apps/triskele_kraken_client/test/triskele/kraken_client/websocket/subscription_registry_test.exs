defmodule Triskele.KrakenClient.WebSocket.SubscriptionRegistryTest do
  use ExUnit.Case, async: true

  alias Triskele.KrakenClient.WebSocket.SubscriptionRegistry

  @moduletag :phase_1

  describe "new/0" do
    test "returns empty desired and confirmed sets" do
      reg = SubscriptionRegistry.new()
      assert MapSet.size(reg.desired) == 0
      assert MapSet.size(reg.confirmed) == 0
    end
  end

  describe "add_desired/3" do
    test "adds channel+symbol to desired" do
      reg = SubscriptionRegistry.add_desired(SubscriptionRegistry.new(), "book", "BTC/USD")
      assert MapSet.member?(reg.desired, {"book", "BTC/USD"})
    end

    test "accepts nil symbol for private channels" do
      reg = SubscriptionRegistry.add_desired(SubscriptionRegistry.new(), "executions", nil)
      assert MapSet.member?(reg.desired, {"executions", nil})
    end

    test "adding the same key twice is idempotent" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "ETH/USD")
        |> SubscriptionRegistry.add_desired("book", "ETH/USD")

      assert MapSet.size(reg.desired) == 1
    end
  end

  describe "mark_confirmed/3" do
    test "adds to confirmed without touching desired" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "BTC/USD")
        |> SubscriptionRegistry.mark_confirmed("book", "BTC/USD")

      assert MapSet.member?(reg.confirmed, {"book", "BTC/USD"})
      assert MapSet.member?(reg.desired, {"book", "BTC/USD"})
    end

    test "can confirm a key that was never in desired" do
      reg = SubscriptionRegistry.mark_confirmed(SubscriptionRegistry.new(), "ticker", "ETH/USD")

      assert MapSet.member?(reg.confirmed, {"ticker", "ETH/USD"})
      refute MapSet.member?(reg.desired, {"ticker", "ETH/USD"})
    end
  end

  describe "mark_rejected/3" do
    test "removes from both desired and confirmed" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "BTC/USD")
        |> SubscriptionRegistry.mark_confirmed("book", "BTC/USD")
        |> SubscriptionRegistry.mark_rejected("book", "BTC/USD")

      refute MapSet.member?(reg.desired, {"book", "BTC/USD"})
      refute MapSet.member?(reg.confirmed, {"book", "BTC/USD"})
    end

    test "is a no-op for an unknown key" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "ETH/USD")
        |> SubscriptionRegistry.mark_rejected("book", "BTC/USD")

      assert MapSet.member?(reg.desired, {"book", "ETH/USD"})
    end
  end

  describe "remove_desired/3" do
    test "removes from both sets" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("ticker", "BTC/USD")
        |> SubscriptionRegistry.mark_confirmed("ticker", "BTC/USD")
        |> SubscriptionRegistry.remove_desired("ticker", "BTC/USD")

      refute MapSet.member?(reg.desired, {"ticker", "BTC/USD"})
      refute MapSet.member?(reg.confirmed, {"ticker", "BTC/USD"})
    end
  end

  describe "clear_confirmed/1" do
    test "clears confirmed but preserves desired — the resubscribe-after-reconnect contract" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "BTC/USD")
        |> SubscriptionRegistry.add_desired("ticker", "ETH/USD")
        |> SubscriptionRegistry.mark_confirmed("book", "BTC/USD")
        |> SubscriptionRegistry.mark_confirmed("ticker", "ETH/USD")
        |> SubscriptionRegistry.clear_confirmed()

      # confirmed is empty
      assert MapSet.size(reg.confirmed) == 0

      # desired is intact — this is what drives resubscription after reconnect
      assert MapSet.member?(reg.desired, {"book", "BTC/USD"})
      assert MapSet.member?(reg.desired, {"ticker", "ETH/USD"})
    end

    test "is idempotent on an already-empty confirmed set" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "SOL/USD")
        |> SubscriptionRegistry.clear_confirmed()
        |> SubscriptionRegistry.clear_confirmed()

      assert MapSet.size(reg.confirmed) == 0
      assert MapSet.member?(reg.desired, {"book", "SOL/USD"})
    end
  end

  describe "unconfirm/3" do
    test "removes from confirmed but leaves desired intact" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "BTC/USD")
        |> SubscriptionRegistry.mark_confirmed("book", "BTC/USD")
        |> SubscriptionRegistry.unconfirm("book", "BTC/USD")

      refute MapSet.member?(reg.confirmed, {"book", "BTC/USD"})
      assert MapSet.member?(reg.desired, {"book", "BTC/USD"})
    end

    test "is a no-op when key is not confirmed" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "ETH/USD")
        |> SubscriptionRegistry.unconfirm("book", "ETH/USD")

      assert MapSet.size(reg.confirmed) == 0
      assert MapSet.member?(reg.desired, {"book", "ETH/USD"})
    end
  end

  describe "resubscribe_list/1" do
    test "groups desired subscriptions by channel" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "BTC/USD")
        |> SubscriptionRegistry.add_desired("book", "ETH/USD")
        |> SubscriptionRegistry.add_desired("ticker", "BTC/USD")

      list = SubscriptionRegistry.resubscribe_list(reg)

      assert is_list(list["book"])
      assert length(list["book"]) == 2
      assert "BTC/USD" in list["book"]
      assert "ETH/USD" in list["book"]
      assert list["ticker"] == ["BTC/USD"]
    end

    test "returns empty map when desired is empty" do
      assert SubscriptionRegistry.resubscribe_list(SubscriptionRegistry.new()) == %{}
    end

    test "includes all desired regardless of confirmed state" do
      reg =
        SubscriptionRegistry.new()
        |> SubscriptionRegistry.add_desired("book", "BTC/USD")
        |> SubscriptionRegistry.add_desired("book", "ETH/USD")
        |> SubscriptionRegistry.mark_confirmed("book", "BTC/USD")

      list = SubscriptionRegistry.resubscribe_list(reg)
      assert length(list["book"]) == 2
    end
  end
end
