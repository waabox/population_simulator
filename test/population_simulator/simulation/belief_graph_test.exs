defmodule PopulationSimulator.Simulation.BeliefGraphTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.BeliefGraph

  @base_graph %{
    "nodes" => [
      %{"id" => "inflation", "type" => "core"},
      %{"id" => "employment", "type" => "core"},
      %{"id" => "taxes", "type" => "core"}
    ],
    "edges" => [
      %{"from" => "inflation", "to" => "employment", "type" => "causal", "weight" => -0.5},
      %{"from" => "taxes", "to" => "employment", "type" => "causal", "weight" => -0.3}
    ]
  }

  describe "apply_delta/2 with bounds" do
    test "caps total nodes at max (15 core + 10 emergent)" do
      existing_emergent = Enum.map(1..9, &%{"id" => "emergent_#{&1}", "type" => "emergent"})
      core = Enum.map(BeliefGraph.core_nodes(), &%{"id" => &1, "type" => "core"})
      graph = %{"nodes" => core ++ existing_emergent, "edges" => []}

      delta = %{
        "new_nodes" => [
          %{"id" => "new_concept_a", "type" => "emergent"},
          %{"id" => "new_concept_b", "type" => "emergent"},
          %{"id" => "new_concept_c", "type" => "emergent"}
        ],
        "new_edges" => [], "modified_edges" => [], "removed_edges" => []
      }

      result = BeliefGraph.apply_delta(graph, delta)
      emergent_count = result["nodes"] |> Enum.count(&(&1["type"] == "emergent"))
      assert emergent_count <= 10
    end

    test "caps total edges at 40" do
      edges = Enum.map(1..38, fn i ->
        %{"from" => "taxes", "to" => "employment", "type" => "causal", "weight" => 0.1, "idx" => i}
      end)
      graph = %{"nodes" => @base_graph["nodes"], "edges" => edges}

      delta = %{
        "new_nodes" => [],
        "new_edges" => Enum.map(1..5, fn i ->
          %{"from" => "inflation", "to" => "taxes", "type" => "emotional", "weight" => 0.2, "idx" => 100 + i}
        end),
        "modified_edges" => [], "removed_edges" => []
      }

      result = BeliefGraph.apply_delta(graph, delta)
      assert length(result["edges"]) <= 40
    end
  end

  describe "apply_edge_damping/3" do
    test "dampens large weight changes" do
      previous = %{
        "edges" => [
          %{"from" => "taxes", "to" => "employment", "type" => "causal", "weight" => 0.3}
        ]
      }

      new = %{
        "edges" => [
          %{"from" => "taxes", "to" => "employment", "type" => "causal", "weight" => 0.9}
        ]
      }

      dampened = BeliefGraph.apply_edge_damping(new, previous, 0.5)
      edge = hd(dampened["edges"])
      assert edge["weight"] <= 0.8
      assert edge["weight"] >= 0.3
    end

    test "preserves edges with small changes" do
      previous = %{"edges" => [%{"from" => "taxes", "to" => "employment", "type" => "causal", "weight" => 0.3}]}
      new = %{"edges" => [%{"from" => "taxes", "to" => "employment", "type" => "causal", "weight" => 0.5}]}

      dampened = BeliefGraph.apply_edge_damping(new, previous, 0.5)
      edge = hd(dampened["edges"])
      assert edge["weight"] == 0.5
    end
  end

  describe "decay_emergent_nodes/2" do
    test "removes emergent nodes not reinforced after N measures" do
      graph = %{
        "nodes" => [
          %{"id" => "inflation", "type" => "core"},
          %{"id" => "old_concept", "type" => "emergent", "added_at" => "Medida 1", "last_reinforced" => 0},
          %{"id" => "fresh_concept", "type" => "emergent", "added_at" => "Medida 5", "last_reinforced" => 4}
        ],
        "edges" => [
          %{"from" => "old_concept", "to" => "inflation", "type" => "causal", "weight" => 0.3},
          %{"from" => "fresh_concept", "to" => "inflation", "type" => "causal", "weight" => 0.5}
        ]
      }

      result = BeliefGraph.decay_emergent_nodes(graph, 5, 3)

      node_ids = Enum.map(result["nodes"], & &1["id"])
      assert "inflation" in node_ids
      assert "fresh_concept" in node_ids
      refute "old_concept" in node_ids

      edge_froms = Enum.map(result["edges"], & &1["from"])
      refute "old_concept" in edge_froms
    end

    test "never removes core nodes" do
      graph = %{
        "nodes" => [%{"id" => "inflation", "type" => "core"}],
        "edges" => []
      }

      result = BeliefGraph.decay_emergent_nodes(graph, 100, 3)
      assert length(result["nodes"]) == 1
    end
  end
end
