defmodule PopulationSimulator.Simulation.ConsistencyCheckerTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.ConsistencyChecker

  describe "check/3" do
    test "flags high economic_confidence for destitute actor after austerity" do
      profile = %{"stratum" => "destitute", "employment_type" => "unemployed"}
      response = %{
        intensity: 9,
        agreement: true,
        mood_update: %{
          "economic_confidence" => 9,
          "government_trust" => 5,
          "personal_wellbeing" => 5,
          "social_anger" => 5,
          "future_outlook" => 5
        }
      }
      measure_tags = ["austerity", "cut"]

      {adjusted, warnings} = ConsistencyChecker.check(response, profile, measure_tags)

      assert length(warnings) > 0
      assert adjusted.mood_update["economic_confidence"] < 9
    end

    test "flags low social_anger for destitute actor after cut" do
      profile = %{"stratum" => "destitute", "employment_type" => "unemployed"}
      response = %{
        intensity: 3,
        agreement: false,
        mood_update: %{
          "economic_confidence" => 3,
          "government_trust" => 2,
          "personal_wellbeing" => 3,
          "social_anger" => 1,
          "future_outlook" => 3
        }
      }
      measure_tags = ["cut"]

      {adjusted, warnings} = ConsistencyChecker.check(response, profile, measure_tags)

      assert length(warnings) > 0
      assert adjusted.mood_update["social_anger"] > 1
    end

    test "no warnings for consistent response" do
      profile = %{"stratum" => "middle", "employment_type" => "formal_employee"}
      response = %{
        intensity: 6,
        agreement: true,
        mood_update: %{
          "economic_confidence" => 6,
          "government_trust" => 6,
          "personal_wellbeing" => 6,
          "social_anger" => 4,
          "future_outlook" => 6
        }
      }
      measure_tags = ["stimulus"]

      {_adjusted, warnings} = ConsistencyChecker.check(response, profile, measure_tags)
      assert warnings == []
    end

    test "flags extreme agreement intensity for opposed orientation" do
      profile = %{
        "stratum" => "middle",
        "political_orientation" => 2,
        "employment_type" => "formal_employee"
      }
      response = %{
        intensity: 10,
        agreement: true,
        mood_update: %{
          "economic_confidence" => 8,
          "government_trust" => 9,
          "personal_wellbeing" => 7,
          "social_anger" => 2,
          "future_outlook" => 8
        }
      }
      measure_tags = ["liberal", "deregulation"]

      {adjusted, warnings} = ConsistencyChecker.check(response, profile, measure_tags)

      assert length(warnings) > 0
      assert adjusted.intensity < 10
    end

    test "returns response unchanged when no mood_update" do
      profile = %{"stratum" => "middle", "employment_type" => "formal_employee"}
      response = %{intensity: 5, agreement: true, mood_update: nil}
      measure_tags = []

      {adjusted, warnings} = ConsistencyChecker.check(response, profile, measure_tags)
      assert warnings == []
      assert adjusted == response
    end
  end
end
