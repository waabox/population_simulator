defmodule PopulationSimulator.Simulation.EventResponseValidatorTest do
  use ExUnit.Case, async: true
  alias PopulationSimulator.Simulation.EventResponseValidator
  @valid_response %{
    "event" => "Me echaron del taller.",
    "mood_impact" => %{"economic_confidence" => -1.5, "social_anger" => 0.8},
    "profile_effects" => %{"employment_status" => "unemployed", "income_delta" => -350_000},
    "duration" => 4
  }
  test "validates a correct response" do
    assert {:ok, validated} = EventResponseValidator.validate(@valid_response, 500_000)
    assert validated["event"] == "Me echaron del taller."
    assert validated["duration"] == 4
  end
  test "clamps mood_impact to +-2.0" do
    response = put_in(@valid_response, ["mood_impact", "economic_confidence"], -3.5)
    assert {:ok, validated} = EventResponseValidator.validate(response, 500_000)
    assert validated["mood_impact"]["economic_confidence"] == -2.0
  end
  test "clamps income_delta to +-70% of current income" do
    response = put_in(@valid_response, ["profile_effects", "income_delta"], -900_000)
    assert {:ok, validated} = EventResponseValidator.validate(response, 500_000)
    assert validated["profile_effects"]["income_delta"] == -350_000
  end
  test "clamps duration to 1-6" do
    response = Map.put(@valid_response, "duration", 10)
    assert {:ok, validated} = EventResponseValidator.validate(response, 500_000)
    assert validated["duration"] == 6
  end
  test "strips unrecognized profile_effects fields" do
    response = put_in(@valid_response, ["profile_effects", "secret_power"], "fly")
    assert {:ok, validated} = EventResponseValidator.validate(response, 500_000)
    refute Map.has_key?(validated["profile_effects"], "secret_power")
  end
  test "rejects response missing event description" do
    response = Map.delete(@valid_response, "event")
    assert {:error, _} = EventResponseValidator.validate(response, 500_000)
  end
end
