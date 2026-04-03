defmodule PopulationSimulator.Simulation.CafeResponseValidatorTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.CafeResponseValidator

  @valid_response %{
    "conversation" => [
      %{"actor_id" => "a1", "name" => "María", "message" => "Hola"},
      %{"actor_id" => "a2", "name" => "Jorge", "message" => "Qué tal"}
    ],
    "conversation_summary" => "Hablaron de la medida.",
    "effects" => [
      %{
        "actor_id" => "a1",
        "mood_deltas" => %{"economic_confidence" => 0.5, "social_anger" => -0.3},
        "belief_deltas" => %{"modified_edges" => [], "new_nodes" => []}
      },
      %{
        "actor_id" => "a2",
        "mood_deltas" => %{"economic_confidence" => -0.2},
        "belief_deltas" => %{"modified_edges" => [%{"from" => "dollar", "to" => "inflation", "weight_delta" => 0.2}], "new_nodes" => []}
      }
    ]
  }

  @actor_ids ["a1", "a2"]

  test "validates a correct response" do
    assert {:ok, validated} = CafeResponseValidator.validate(@valid_response, @actor_ids)
    assert length(validated["conversation"]) == 2
    assert length(validated["effects"]) == 2
  end

  test "clamps mood deltas exceeding +-1.0" do
    response = put_in(@valid_response, ["effects", Access.at(0), "mood_deltas", "economic_confidence"], 2.5)
    assert {:ok, validated} = CafeResponseValidator.validate(response, @actor_ids)
    effect = Enum.find(validated["effects"], &(&1["actor_id"] == "a1"))
    assert effect["mood_deltas"]["economic_confidence"] == 1.0
  end

  test "rejects more than 2 modified edges per actor" do
    edges = [
      %{"from" => "a", "to" => "b", "weight_delta" => 0.1},
      %{"from" => "c", "to" => "d", "weight_delta" => 0.1},
      %{"from" => "e", "to" => "f", "weight_delta" => 0.1}
    ]
    response = put_in(@valid_response, ["effects", Access.at(0), "belief_deltas", "modified_edges"], edges)
    assert {:ok, validated} = CafeResponseValidator.validate(response, @actor_ids)
    effect = Enum.find(validated["effects"], &(&1["actor_id"] == "a1"))
    assert length(effect["belief_deltas"]["modified_edges"]) == 2
  end

  test "strips new_nodes (not allowed in café)" do
    response = put_in(@valid_response, ["effects", Access.at(0), "belief_deltas", "new_nodes"], [%{"id" => "test"}])
    assert {:ok, validated} = CafeResponseValidator.validate(response, @actor_ids)
    effect = Enum.find(validated["effects"], &(&1["actor_id"] == "a1"))
    assert effect["belief_deltas"]["new_nodes"] == []
  end

  test "rejects response missing conversation" do
    response = Map.delete(@valid_response, "conversation")
    assert {:error, _} = CafeResponseValidator.validate(response, @actor_ids)
  end
end
