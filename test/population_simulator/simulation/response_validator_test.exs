defmodule PopulationSimulator.Simulation.ResponseValidatorTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.ResponseValidator

  describe "validate/1" do
    test "accepts valid complete response" do
      response = %{
        agreement: true,
        intensity: 7,
        reasoning: "Me parece bien la medida.",
        personal_impact: "Me beneficia directamente.",
        behavior_change: "No cambio nada.",
        mood_update: %{
          "economic_confidence" => 6,
          "government_trust" => 7,
          "personal_wellbeing" => 5,
          "social_anger" => 3,
          "future_outlook" => 6,
          "narrative" => "Me siento tranquilo."
        },
        belief_update: %{
          "modified_edges" => [%{"from" => "taxes", "to" => "wages", "type" => "causal", "weight" => 0.5}],
          "new_edges" => [],
          "new_nodes" => [],
          "removed_edges" => []
        }
      }

      assert {:ok, ^response} = ResponseValidator.validate(response)
    end

    test "clamps intensity to 1-10" do
      response = valid_response(%{intensity: 15})
      {:ok, validated} = ResponseValidator.validate(response)
      assert validated.intensity == 10
    end

    test "clamps intensity below 1" do
      response = valid_response(%{intensity: -3})
      {:ok, validated} = ResponseValidator.validate(response)
      assert validated.intensity == 1
    end

    test "rejects non-boolean agreement" do
      response = valid_response(%{agreement: "yes"})
      assert {:error, reason} = ResponseValidator.validate(response)
      assert reason =~ "agreement"
    end

    test "truncates reasoning to 500 chars" do
      long = String.duplicate("a", 600)
      response = valid_response(%{reasoning: long})
      {:ok, validated} = ResponseValidator.validate(response)
      assert String.length(validated.reasoning) <= 500
    end

    test "truncates narrative to 300 chars" do
      long = String.duplicate("a", 400)
      response = valid_response(%{mood_update: %{
        "economic_confidence" => 5, "government_trust" => 5,
        "personal_wellbeing" => 5, "social_anger" => 5,
        "future_outlook" => 5, "narrative" => long
      }})
      {:ok, validated} = ResponseValidator.validate(response)
      assert String.length(validated.mood_update["narrative"]) <= 300
    end

    test "clamps mood values to 1-10" do
      response = valid_response(%{mood_update: %{
        "economic_confidence" => 15, "government_trust" => -2,
        "personal_wellbeing" => 5, "social_anger" => 5,
        "future_outlook" => 5, "narrative" => "ok"
      }})
      {:ok, validated} = ResponseValidator.validate(response)
      assert validated.mood_update["economic_confidence"] == 10
      assert validated.mood_update["government_trust"] == 1
    end

    test "limits new_nodes to max 3" do
      nodes = Enum.map(1..6, &%{"id" => "node_#{&1}", "type" => "emergent"})
      response = valid_response(%{belief_update: %{
        "modified_edges" => [], "new_edges" => [],
        "new_nodes" => nodes, "removed_edges" => []
      }})
      {:ok, validated} = ResponseValidator.validate(response)
      assert length(validated.belief_update["new_nodes"]) == 3
    end

    test "limits new_edges to max 5" do
      edges = Enum.map(1..8, &%{"from" => "taxes", "to" => "node_#{&1}", "type" => "causal", "weight" => 0.3})
      response = valid_response(%{belief_update: %{
        "modified_edges" => [], "new_edges" => edges,
        "new_nodes" => [], "removed_edges" => []
      }})
      {:ok, validated} = ResponseValidator.validate(response)
      assert length(validated.belief_update["new_edges"]) == 5
    end

    test "limits modified_edges to max 5" do
      edges = Enum.map(1..8, &%{"from" => "taxes", "to" => "node_#{&1}", "type" => "causal", "weight" => 0.3})
      response = valid_response(%{belief_update: %{
        "modified_edges" => edges, "new_edges" => [],
        "new_nodes" => [], "removed_edges" => []
      }})
      {:ok, validated} = ResponseValidator.validate(response)
      assert length(validated.belief_update["modified_edges"]) == 5
    end

    test "validates node ID format (snake_case, max 30 chars)" do
      nodes = [%{"id" => "This Is NOT Valid!!", "type" => "emergent"}]
      response = valid_response(%{belief_update: %{
        "modified_edges" => [], "new_edges" => [],
        "new_nodes" => nodes, "removed_edges" => []
      }})
      {:ok, validated} = ResponseValidator.validate(response)
      assert validated.belief_update["new_nodes"] == []
    end

    test "accepts nil mood_update and belief_update" do
      response = %{
        agreement: true, intensity: 5,
        reasoning: "Ok.", personal_impact: "Nada.",
        behavior_change: "Nada.", mood_update: nil,
        belief_update: nil, tokens_used: 100, raw_response: %{}
      }
      assert {:ok, _} = ResponseValidator.validate(response)
    end
  end

  defp valid_response(overrides) do
    Map.merge(%{
      agreement: true,
      intensity: 5,
      reasoning: "Razonable.",
      personal_impact: "Me afecta poco.",
      behavior_change: "Nada.",
      mood_update: %{
        "economic_confidence" => 5, "government_trust" => 5,
        "personal_wellbeing" => 5, "social_anger" => 5,
        "future_outlook" => 5, "narrative" => "Normal."
      },
      belief_update: %{
        "modified_edges" => [], "new_edges" => [],
        "new_nodes" => [], "removed_edges" => []
      },
      tokens_used: 100,
      raw_response: %{}
    }, overrides)
  end
end
