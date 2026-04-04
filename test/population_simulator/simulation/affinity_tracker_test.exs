defmodule PopulationSimulator.Simulation.AffinityTrackerTest do
  use ExUnit.Case, async: true
  alias PopulationSimulator.Simulation.AffinityTracker

  describe "pairs_from_table/1" do
    test "generates all unique ordered pairs" do
      actor_ids = ["c", "a", "b"]
      pairs = AffinityTracker.pairs_from_table(actor_ids)
      assert length(pairs) == 3
      assert {"a", "b"} in pairs
      assert {"a", "c"} in pairs
      assert {"b", "c"} in pairs
    end
    test "single actor produces no pairs" do
      assert AffinityTracker.pairs_from_table(["a"]) == []
    end
    test "two actors produce one pair" do
      pairs = AffinityTracker.pairs_from_table(["b", "a"])
      assert pairs == [{"a", "b"}]
    end
  end
end
