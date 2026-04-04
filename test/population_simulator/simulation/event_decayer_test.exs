defmodule PopulationSimulator.Simulation.EventDecayerTest do
  use ExUnit.Case, async: true
  alias PopulationSimulator.Simulation.EventDecayer

  describe "decayed_impact/3" do
    test "full impact when remaining equals duration" do
      original = %{"economic_confidence" => -2.0, "social_anger" => 1.0}
      result = EventDecayer.decayed_impact(original, 4, 4)
      assert result["economic_confidence"] == -2.0
      assert result["social_anger"] == 1.0
    end
    test "half impact when remaining is half of duration" do
      original = %{"economic_confidence" => -2.0}
      result = EventDecayer.decayed_impact(original, 2, 4)
      assert_in_delta result["economic_confidence"], -1.0, 0.01
    end
    test "zero impact when remaining is 0" do
      original = %{"economic_confidence" => -2.0}
      result = EventDecayer.decayed_impact(original, 0, 4)
      assert result["economic_confidence"] == 0.0
    end
  end

  describe "aggregate_active_impacts/1" do
    test "sums decayed impacts from multiple events" do
      events = [
        %{mood_impact: %{"economic_confidence" => -2.0, "social_anger" => 1.0}, duration: 4, remaining: 4},
        %{mood_impact: %{"economic_confidence" => 1.0, "personal_wellbeing" => -1.5}, duration: 3, remaining: 1}
      ]
      result = EventDecayer.aggregate_active_impacts(events)
      assert_in_delta result["economic_confidence"], -2.0 + 1.0 / 3, 0.01
      assert_in_delta result["social_anger"], 1.0, 0.01
      assert_in_delta result["personal_wellbeing"], -1.5 / 3, 0.01
    end
    test "empty events returns empty map" do
      assert EventDecayer.aggregate_active_impacts([]) == %{}
    end
  end
end
