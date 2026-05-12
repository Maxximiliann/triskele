defmodule Triskele.Util.TimeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Triskele.Util.Time

  describe "utc_now/0" do
    test "returns a DateTime in Etc/UTC" do
      dt = Time.utc_now()
      assert %DateTime{} = dt
      assert dt.time_zone == "Etc/UTC"
    end
  end

  describe "monotonic_us/0" do
    test "returns an integer" do
      assert is_integer(Time.monotonic_us())
    end

    test "is monotonically non-decreasing" do
      t1 = Time.monotonic_us()
      t2 = Time.monotonic_us()
      assert t2 >= t1
    end
  end

  describe "to_display/1" do
    test "shifts a UTC datetime to America/Denver (MST, UTC-7 in winter)" do
      # 2024-01-15 12:00:00 UTC = 2024-01-15 05:00:00 MST
      utc_dt = DateTime.new!(~D[2024-01-15], ~T[12:00:00], "Etc/UTC")
      denver_dt = Time.to_display(utc_dt)

      assert denver_dt.time_zone == "America/Denver"
      assert denver_dt.hour == 5
      assert denver_dt.minute == 0
      assert denver_dt.day == 15
      assert denver_dt.month == 1
      assert denver_dt.year == 2024
    end

    test "shifts a UTC datetime to America/Denver (MDT, UTC-6 in summer)" do
      # 2024-07-15 12:00:00 UTC = 2024-07-15 06:00:00 MDT
      utc_dt = DateTime.new!(~D[2024-07-15], ~T[12:00:00], "Etc/UTC")
      denver_dt = Time.to_display(utc_dt)

      assert denver_dt.time_zone == "America/Denver"
      assert denver_dt.hour == 6
      assert denver_dt.minute == 0
      assert denver_dt.day == 15
    end

    test "crosses midnight correctly (UTC midnight is prior-day evening in Denver)" do
      # 2024-01-01 00:00:00 UTC = 2023-12-31 17:00:00 MST
      utc_dt = DateTime.new!(~D[2024-01-01], ~T[00:00:00], "Etc/UTC")
      denver_dt = Time.to_display(utc_dt)

      assert denver_dt.year == 2023
      assert denver_dt.month == 12
      assert denver_dt.day == 31
      assert denver_dt.hour == 17
    end
  end

  describe "to_local_date/1" do
    test "returns the Denver-local date, not the UTC date" do
      # A trade at 2024-01-01 04:00:00 UTC is still 2023-12-31 in Denver (MST)
      utc_dt = DateTime.new!(~D[2024-01-01], ~T[04:00:00], "Etc/UTC")
      local_date = Time.to_local_date(utc_dt)

      assert local_date == ~D[2023-12-31]
    end

    test "returns the same date when UTC and Denver agree" do
      # 2024-06-15 20:00:00 UTC = 2024-06-15 14:00:00 MDT — same calendar date
      utc_dt = DateTime.new!(~D[2024-06-15], ~T[20:00:00], "Etc/UTC")
      local_date = Time.to_local_date(utc_dt)

      assert local_date == ~D[2024-06-15]
    end
  end

  describe "format_display/1" do
    test "produces a formatted string in Denver time (MST in winter)" do
      # 2024-01-15 12:00:00 UTC = 2024-01-15 05:00:00 MST
      utc_dt = DateTime.new!(~D[2024-01-15], ~T[12:00:00], "Etc/UTC")
      result = Time.format_display(utc_dt)

      assert result == "2024-01-15 05:00:00 MST"
    end

    test "produces a formatted string in Denver time (MDT in summer)" do
      # 2024-07-15 12:00:00 UTC = 2024-07-15 06:00:00 MDT
      utc_dt = DateTime.new!(~D[2024-07-15], ~T[12:00:00], "Etc/UTC")
      result = Time.format_display(utc_dt)

      assert result == "2024-07-15 06:00:00 MDT"
    end
  end
end
