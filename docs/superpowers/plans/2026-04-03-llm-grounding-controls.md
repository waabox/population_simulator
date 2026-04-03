# LLM Grounding Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the LLM from "inventing sociology" by adding 5 layers of controls: rule constraints, bounded belief updates, calibration loops, consistency checks, and repeated-run variance analysis.

**Architecture:** New module `ResponseValidator` validates LLM responses before persistence. `BeliefGraph` gets damping and size limits. `ConsistencyChecker` applies demographic-grounded rules post-response. New mix tasks `sim.calibrate` and `sim.variance` provide meta-analysis tools. All controls integrate into MeasureRunner's existing flow.

**Tech Stack:** Elixir/OTP, Ecto, SQLite3, existing simulation modules.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `lib/population_simulator/simulation/response_validator.ex` | **NEW** — Schema validation + rule constraints for LLM responses |
| `lib/population_simulator/simulation/consistency_checker.ex` | **NEW** — Demographic consistency checks post-response |
| `lib/population_simulator/simulation/belief_graph.ex` | **MODIFY** — Add node/edge limits, edge damping, emergent decay |
| `lib/population_simulator/simulation/decision.ex` | **MODIFY** — Add intensity bounds validation |
| `lib/population_simulator/llm/claude_client.ex` | **MODIFY** — Add temperature parameter |
| `lib/population_simulator/simulation/measure_runner.ex` | **MODIFY** — Integrate validator + consistency checker + belief bounds |
| `lib/population_simulator/simulation/prompt_builder.ex` | **MODIFY** — Strengthen belief update instructions with limits |
| `lib/mix/tasks/sim.calibrate.ex` | **NEW** — Calibration loop: same measure N times, measure variance |
| `lib/mix/tasks/sim.variance.ex` | **NEW** — Repeated-run variance analysis + consensus detection |
| `test/population_simulator/simulation/response_validator_test.exs` | **NEW** — Tests for response validation |
| `test/population_simulator/simulation/consistency_checker_test.exs` | **NEW** — Tests for consistency checks |
| `test/population_simulator/simulation/belief_graph_test.exs` | **NEW** — Tests for belief bounds and damping |

---

## Task 1: ResponseValidator — Schema Validation & Rule Constraints

**Files:**
- Create: `lib/population_simulator/simulation/response_validator.ex`
- Create: `test/population_simulator/simulation/response_validator_test.exs`

This module validates the raw parsed LLM response before it hits persistence. It enforces structural rules (required fields, type checks, range bounds) and semantic rules (intensity bounds, narrative length, belief delta limits).

- [ ] **Step 1: Write failing tests for response validation**

```elixir
# test/population_simulator/simulation/response_validator_test.exs
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/response_validator_test.exs`
Expected: Compilation error — `ResponseValidator` module not found.

- [ ] **Step 3: Implement ResponseValidator**

```elixir
# lib/population_simulator/simulation/response_validator.ex
defmodule PopulationSimulator.Simulation.ResponseValidator do
  @moduledoc """
  Validates and sanitizes LLM responses before persistence.
  Enforces structural rules (types, ranges) and semantic limits
  (narrative length, belief delta sizes, node ID format).
  """

  @max_reasoning_length 500
  @max_narrative_length 300
  @max_new_nodes 3
  @max_new_edges 5
  @max_modified_edges 5
  @node_id_pattern ~r/^[a-z][a-z0-9_]{0,29}$/

  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)

  def validate(response) when is_map(response) do
    with :ok <- validate_agreement(response.agreement),
         response <- clamp_intensity(response),
         response <- truncate_text_fields(response),
         response <- validate_mood_update(response),
         response <- validate_belief_update(response) do
      {:ok, response}
    end
  end

  defp validate_agreement(val) when is_boolean(val), do: :ok
  defp validate_agreement(_), do: {:error, "agreement must be boolean"}

  defp clamp_intensity(response) do
    %{response | intensity: clamp(response.intensity, 1, 10)}
  end

  defp truncate_text_fields(response) do
    response
    |> Map.update(:reasoning, nil, &truncate(&1, @max_reasoning_length))
    |> Map.update(:personal_impact, nil, &truncate(&1, @max_reasoning_length))
    |> Map.update(:behavior_change, nil, &truncate(&1, @max_reasoning_length))
  end

  defp validate_mood_update(%{mood_update: nil} = response), do: response
  defp validate_mood_update(%{mood_update: mood} = response) when is_map(mood) do
    clamped = Enum.reduce(@mood_dimensions, mood, fn dim, acc ->
      Map.update(acc, dim, 5, &clamp(&1, 1, 10))
    end)

    clamped = Map.update(clamped, "narrative", nil, &truncate(&1, @max_narrative_length))
    %{response | mood_update: clamped}
  end
  defp validate_mood_update(response), do: response

  defp validate_belief_update(%{belief_update: nil} = response), do: response
  defp validate_belief_update(%{belief_update: delta} = response) when is_map(delta) do
    validated = delta
    |> Map.update("new_nodes", [], &filter_and_limit_nodes/1)
    |> Map.update("new_edges", [], &Enum.take(&1, @max_new_edges))
    |> Map.update("modified_edges", [], &Enum.take(&1, @max_modified_edges))

    %{response | belief_update: validated}
  end
  defp validate_belief_update(response), do: response

  defp filter_and_limit_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.filter(fn node ->
      id = node["id"]
      is_binary(id) and Regex.match?(@node_id_pattern, id)
    end)
    |> Enum.take(@max_new_nodes)
  end
  defp filter_and_limit_nodes(_), do: []

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, min_v, _), do: min_v

  defp truncate(nil, _), do: nil
  defp truncate(text, max) when is_binary(text) and byte_size(text) > max do
    String.slice(text, 0, max)
  end
  defp truncate(text, _), do: text
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/population_simulator/simulation/response_validator_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```
Add ResponseValidator for LLM response schema validation and rule constraints
```

---

## Task 2: Decision Intensity Bounds + ClaudeClient Temperature

**Files:**
- Modify: `lib/population_simulator/simulation/decision.ex:20-34`
- Modify: `lib/population_simulator/llm/claude_client.ex:14-18`

- [ ] **Step 1: Add intensity validation to Decision changeset**

In `lib/population_simulator/simulation/decision.ex`, update `changeset/2`:

```elixir
def changeset(decision, attrs) do
  decision
  |> cast(attrs, [
    :actor_id,
    :measure_id,
    :agreement,
    :intensity,
    :reasoning,
    :personal_impact,
    :behavior_change,
    :raw_response,
    :tokens_used
  ])
  |> validate_required([:actor_id, :measure_id])
  |> validate_number(:intensity, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
end
```

- [ ] **Step 2: Add temperature parameter to ClaudeClient**

In `lib/population_simulator/llm/claude_client.ex`, update `complete/2` to include temperature in the body:

```elixir
def complete(prompt, opts \\ []) do
  model = Keyword.get(opts, :model, Application.get_env(:population_simulator, :claude_model, "claude-haiku-4-5-20251001"))
  max_tokens = Keyword.get(opts, :max_tokens, 512)
  temperature = Keyword.get(opts, :temperature, 0.3)

  body = %{
    model: model,
    max_tokens: max_tokens,
    temperature: temperature,
    messages: [%{role: "user", content: prompt}]
  }
  # ... rest unchanged
```

Temperature 0.3 gives some natural variation without wild hallucination. Temperature 0.0 would make identical profiles give identical responses.

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 4: Commit**

```
Add intensity bounds to Decision changeset and temperature control to ClaudeClient
```

---

## Task 3: BeliefGraph Bounded Updates — Node Cap, Edge Damping, Emergent Decay

**Files:**
- Modify: `lib/population_simulator/simulation/belief_graph.ex`
- Create: `test/population_simulator/simulation/belief_graph_test.exs`

- [ ] **Step 1: Write failing tests for belief bounds**

```elixir
# test/population_simulator/simulation/belief_graph_test.exs
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
      # Start with 15 core + 9 emergent = 24 nodes
      existing_emergent = Enum.map(1..9, &%{"id" => "emergent_#{&1}", "type" => "emergent"})
      core = Enum.map(BeliefGraph.core_nodes(), &%{"id" => &1, "type" => "core"})
      graph = %{"nodes" => core ++ existing_emergent, "edges" => []}

      # Try to add 3 more emergent (would go to 27, should cap at 25)
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
      # Delta was 0.6, with max_delta 0.5 it should be capped
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

      # Current measure index is 5, threshold is 3
      result = BeliefGraph.decay_emergent_nodes(graph, 5, 3)

      node_ids = Enum.map(result["nodes"], & &1["id"])
      assert "inflation" in node_ids
      assert "fresh_concept" in node_ids
      refute "old_concept" in node_ids

      # Edges touching old_concept should also be removed
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/belief_graph_test.exs`
Expected: Fail — functions `apply_edge_damping/3` and `decay_emergent_nodes/3` don't exist, and `apply_delta` doesn't enforce caps.

- [ ] **Step 3: Implement belief bounds in BeliefGraph**

Add these constants and functions to `lib/population_simulator/simulation/belief_graph.ex`:

At the top, after `@core_nodes`:

```elixir
@max_emergent_nodes 10
@max_total_edges 40
```

Replace `add_nodes/2` with bounded version:

```elixir
defp add_nodes(graph, []), do: graph
defp add_nodes(graph, new_nodes) do
  existing = graph["nodes"] || []
  existing_ids = Enum.map(existing, & &1["id"]) |> MapSet.new()
  emergent_count = Enum.count(existing, &(&1["type"] == "emergent"))

  unique_new = Enum.reject(new_nodes, fn n -> MapSet.member?(existing_ids, n["id"]) end)
  slots = max(@max_emergent_nodes - emergent_count, 0)
  capped = Enum.take(unique_new, slots)

  Map.update(graph, "nodes", capped, &(&1 ++ capped))
end
```

Replace `add_edges/2` with bounded version:

```elixir
defp add_edges(graph, []), do: graph
defp add_edges(graph, new_edges) do
  existing = graph["edges"] || []
  existing_set = MapSet.new(existing, fn e -> {e["from"], e["to"], e["type"]} end)
  unique_new = Enum.reject(new_edges, fn e ->
    MapSet.member?(existing_set, {e["from"], e["to"], e["type"]})
  end)

  slots = max(@max_total_edges - length(existing), 0)
  capped = Enum.take(unique_new, slots)
  Map.update(graph, "edges", capped, &(&1 ++ capped))
end
```

Add new public functions after `apply_delta/2`:

```elixir
@doc """
Dampens edge weight changes that exceed max_delta per measure.
Compares new graph against previous graph and caps weight changes.
"""
def apply_edge_damping(new_graph, previous_graph, max_delta) when is_map(new_graph) and is_map(previous_graph) do
  prev_map = Map.new(previous_graph["edges"] || [], fn e -> {{e["from"], e["to"], e["type"]}, e["weight"]} end)

  Map.update(new_graph, "edges", [], fn edges ->
    Enum.map(edges, fn edge ->
      key = {edge["from"], edge["to"], edge["type"]}
      case Map.get(prev_map, key) do
        nil -> edge
        prev_weight ->
          delta = edge["weight"] - prev_weight
          capped_delta = delta |> max(-max_delta) |> min(max_delta)
          %{edge | "weight" => prev_weight + capped_delta}
      end
    end)
  end)
end

def apply_edge_damping(new_graph, _, _), do: new_graph

@doc """
Removes emergent nodes that haven't been reinforced within `threshold` measures.
Also removes all edges touching those nodes.
`current_measure_index` is the sequential index of the current measure.
"""
def decay_emergent_nodes(graph, current_measure_index, threshold) when is_map(graph) do
  {keep_nodes, remove_ids} = Enum.reduce(graph["nodes"] || [], {[], MapSet.new()}, fn node, {keep, remove} ->
    if node["type"] == "emergent" do
      last = node["last_reinforced"] || 0
      if current_measure_index - last > threshold do
        {keep, MapSet.put(remove, node["id"])}
      else
        {[node | keep], remove}
      end
    else
      {[node | keep], remove}
    end
  end)

  edges = Enum.reject(graph["edges"] || [], fn e ->
    MapSet.member?(remove_ids, e["from"]) or MapSet.member?(remove_ids, e["to"])
  end)

  %{graph | "nodes" => Enum.reverse(keep_nodes), "edges" => edges}
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/population_simulator/simulation/belief_graph_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```
Add belief graph bounds: node cap, edge limit, weight damping, emergent decay
```

---

## Task 4: ConsistencyChecker — Demographic Grounding Rules

**Files:**
- Create: `lib/population_simulator/simulation/consistency_checker.ex`
- Create: `test/population_simulator/simulation/consistency_checker_test.exs`

This module applies post-response checks based on demographic invariants. It doesn't reject responses — it flags violations and can optionally adjust values.

- [ ] **Step 1: Write failing tests**

```elixir
# test/population_simulator/simulation/consistency_checker_test.exs
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/consistency_checker_test.exs`
Expected: Compilation error — `ConsistencyChecker` not found.

- [ ] **Step 3: Implement ConsistencyChecker**

```elixir
# lib/population_simulator/simulation/consistency_checker.ex
defmodule PopulationSimulator.Simulation.ConsistencyChecker do
  @moduledoc """
  Post-response demographic consistency checks.
  Detects implausible mood/decision combinations given the actor's profile
  and adjusts them toward plausible ranges. Returns warnings for logging.
  """

  @doc """
  Checks response consistency against actor profile and measure context.
  Returns {adjusted_response, warnings} where warnings is a list of strings.
  measure_tags is a list of keyword strings characterizing the measure
  (e.g., ["austerity", "cut", "liberal", "stimulus", "deregulation"]).
  """
  def check(response, profile, measure_tags) do
    {response, []}
    |> check_stratum_mood_consistency(profile, measure_tags)
    |> check_orientation_intensity(profile, measure_tags)
  end

  # Rule 1: Destitute/low stratum + austerity/cut → economic_confidence should not be high
  defp check_stratum_mood_consistency({response, warnings}, profile, measure_tags) do
    stratum = profile["stratum"]
    is_vulnerable = stratum in ["destitute", "low"]
    is_negative_measure = Enum.any?(measure_tags, &(&1 in ["austerity", "cut", "recession"]))

    if is_vulnerable and is_negative_measure and response.mood_update != nil do
      {response, warnings}
      |> cap_mood_dimension("economic_confidence", 6,
          "Destitute/low stratum with austerity measure: economic_confidence capped")
      |> floor_mood_dimension("social_anger", 3,
          "Destitute/low stratum with austerity measure: social_anger floored")
    else
      {response, warnings}
    end
  end

  # Rule 2: Strong political orientation + opposing measure → extreme agreement unlikely
  defp check_orientation_intensity({response, warnings}, profile, measure_tags) do
    orientation = profile["political_orientation"]

    cond do
      not is_integer(orientation) ->
        {response, warnings}

      # Left-leaning actor strongly agreeing with liberal measures
      orientation <= 3 and Enum.any?(measure_tags, &(&1 in ["liberal", "deregulation", "privatization"])) and
          response.agreement == true and response.intensity >= 9 ->
        adjusted = %{response | intensity: min(response.intensity, 7)}
        {adjusted, ["Left-leaning actor with liberal measure: intensity capped at 7" | warnings]}

      # Right-leaning actor strongly agreeing with statist measures
      orientation >= 8 and Enum.any?(measure_tags, &(&1 in ["statist", "nationalization", "regulation"])) and
          response.agreement == true and response.intensity >= 9 ->
        adjusted = %{response | intensity: min(response.intensity, 7)}
        {adjusted, ["Right-leaning actor with statist measure: intensity capped at 7" | warnings]}

      true ->
        {response, warnings}
    end
  end

  defp cap_mood_dimension({response, warnings}, dimension, max_val, warning_msg) do
    current = response.mood_update[dimension]

    if is_number(current) and current > max_val do
      updated_mood = Map.put(response.mood_update, dimension, max_val)
      {%{response | mood_update: updated_mood}, [warning_msg | warnings]}
    else
      {response, warnings}
    end
  end

  defp floor_mood_dimension({response, warnings}, dimension, min_val, warning_msg) do
    current = response.mood_update[dimension]

    if is_number(current) and current < min_val do
      updated_mood = Map.put(response.mood_update, dimension, min_val)
      {%{response | mood_update: updated_mood}, [warning_msg | warnings]}
    else
      {response, warnings}
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/population_simulator/simulation/consistency_checker_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```
Add ConsistencyChecker for demographic grounding of LLM responses
```

---

## Task 5: Integrate Controls into MeasureRunner

**Files:**
- Modify: `lib/population_simulator/simulation/measure_runner.ex`
- Modify: `lib/population_simulator/simulation/prompt_builder.ex:146-150`

This integrates ResponseValidator, ConsistencyChecker, and BeliefGraph bounds into the MeasureRunner flow.

- [ ] **Step 1: Add measure_tags extraction to MeasureRunner**

Add after the existing alias line at the top of `measure_runner.ex`:

```elixir
alias PopulationSimulator.Simulation.{ResponseValidator, ConsistencyChecker}
```

Add a helper function to extract measure tags from the description:

```elixir
defp extract_measure_tags(description) when is_binary(description) do
  text = String.downcase(description)
  tags = []
  tags = if String.contains?(text, ["recorte", "ajuste", "reducción", "elimina"]), do: ["cut" | tags], else: tags
  tags = if String.contains?(text, ["austeridad", "deficit"]), do: ["austerity" | tags], else: tags
  tags = if String.contains?(text, ["liberal", "desregul", "libre mercado"]), do: ["liberal" | tags], else: tags
  tags = if String.contains?(text, ["desregul", "privatiz"]), do: ["deregulation" | tags], else: tags
  tags = if String.contains?(text, ["privatiz"]), do: ["privatization" | tags], else: tags
  tags = if String.contains?(text, ["estatal", "nacional", "estatis"]), do: ["statist" | tags], else: tags
  tags = if String.contains?(text, ["estimul", "subsidio", "aumento", "bono"]), do: ["stimulus" | tags], else: tags
  tags = if String.contains?(text, ["regulac", "control"]), do: ["regulation" | tags], else: tags
  tags
end
defp extract_measure_tags(_), do: []
```

- [ ] **Step 2: Modify evaluate_actor to integrate validation pipeline**

In `evaluate_actor/5`, replace the `case ClaudeClient.complete(prompt, max_tokens: 1024) do` block (lines 126-166) with:

```elixir
case ClaudeClient.complete(prompt, max_tokens: 1024) do
  {:ok, decision} ->
    measure_tags = extract_measure_tags(measure.description)

    # Layer 1: Schema validation & rule constraints
    case ResponseValidator.validate(decision) do
      {:ok, validated} ->
        # Layer 4: Consistency checks
        {checked, consistency_warnings} = ConsistencyChecker.check(validated, actor.profile, measure_tags)

        if consistency_warnings != [] do
          IO.puts("  [consistency] Actor #{String.slice(actor.id, 0..7)}: #{Enum.join(consistency_warnings, "; ")}")
        end

        decision_row = Decision.from_llm_response(actor.id, measure_id, checked)

        Repo.insert_all(Decision, [decision_row],
          on_conflict: :nothing,
          conflict_target: [:actor_id, :measure_id]
        )

        if checked.mood_update do
          dampened = ActorMood.apply_extreme_resistance(checked.mood_update, reverted_mood || %{})

          mood_row = ActorMood.from_llm_response(
            actor.id,
            decision_row.id,
            measure_id,
            dampened
          )

          Repo.insert_all(ActorMood, [mood_row], on_conflict: :nothing)
        end

        if current_belief do
          # Layer 2: Apply delta with bounds (node cap + edge limit already in apply_delta)
          updated_graph = BeliefGraph.apply_delta(current_belief, checked.belief_update)

          # Layer 2: Edge weight damping (max 0.4 change per measure)
          updated_graph = BeliefGraph.apply_edge_damping(updated_graph, current_belief, 0.4)

          # Layer 2: Decay unreinforced emergent nodes
          measure_count = count_actor_measures(actor.id)
          updated_graph = BeliefGraph.decay_emergent_nodes(updated_graph, measure_count, 3)

          belief_row = ActorBelief.from_update(
            actor.id,
            decision_row.id,
            measure_id,
            updated_graph
          )

          Repo.insert_all(ActorBelief, [belief_row], on_conflict: :nothing)
        end

        {:ok, actor.id, checked.tokens_used}

      {:error, reason} ->
        {:error, actor.id, "Validation failed: #{reason}"}
    end

  {:error, reason} ->
    {:error, actor.id, reason}
end
```

- [ ] **Step 3: Add count_actor_measures helper**

```elixir
defp count_actor_measures(actor_id) do
  Repo.one(
    from d in "decisions",
      where: d.actor_id == ^actor_id,
      select: count(d.id)
  ) || 0
end
```

- [ ] **Step 4: Strengthen prompt belief instructions**

In `lib/population_simulator/simulation/prompt_builder.ex`, replace the belief_update instructions block (lines 146-150) with:

```elixir
    IMPORTANTE sobre belief_update:
    - Solo incluí edges que esta medida cambió. No repitas todos los edges.
    - Si no cambió ninguna creencia, dejá los arrays vacíos.
    - Máximo 3 nodos emergentes nuevos por medida. Usá IDs en snake_case (ej: "cepo_cambiario").
    - Máximo 5 edges nuevos y 5 modificados por medida.
    - Los cambios de peso deben ser graduales (no saltar de 0.2 a 0.9 de golpe).
    - Solo agregá un nodo emergente si la medida introduce un concepto GENUINAMENTE nuevo que no existe en tus nodos actuales.
```

- [ ] **Step 5: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 6: Commit**

```
Integrate ResponseValidator, ConsistencyChecker, and belief bounds into MeasureRunner
```

---

## Task 6: Calibration Loop — mix sim.calibrate

**Files:**
- Create: `lib/mix/tasks/sim.calibrate.ex`

This mix task runs the same measure N times for a small sample of actors and reports per-dimension variance. High variance = the LLM is generating rather than reasoning from data.

- [ ] **Step 1: Implement sim.calibrate**

```elixir
# lib/mix/tasks/sim.calibrate.ex
defmodule Mix.Tasks.Sim.Calibrate do
  @moduledoc """
  Calibration loop: runs the same measure multiple times for a sample of actors
  and measures response variance. High variance indicates LLM hallucination.

  Usage:
    mix sim.calibrate --measure-id <id> --runs 5 --sample 10

  Does NOT persist results. Only reports variance statistics.
  """

  use Mix.Task

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.BeliefGraph,
                              Simulation.ActorMood, Simulation.ResponseValidator}
  import Ecto.Query

  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      strict: [measure_id: :string, runs: :integer, sample: :integer, population: :string],
      aliases: [m: :measure_id, r: :runs, s: :sample, p: :population]
    )

    measure_id = opts[:measure_id] || raise "Missing --measure-id"
    runs = opts[:runs] || 5
    sample_size = opts[:sample] || 10

    measure = Repo.get!(PopulationSimulator.Simulation.Measure, measure_id)
    actors = load_sample(opts[:population], sample_size)

    IO.puts("=== CALIBRATION RUN ===")
    IO.puts("Measure: #{measure.title}")
    IO.puts("Actors: #{length(actors)} | Runs per actor: #{runs}")
    IO.puts("")

    relevant = BeliefGraph.relevant_nodes(measure.description)

    results = Enum.map(actors, fn actor ->
      current_mood = load_latest_mood(actor.id)
      current_belief = load_latest_belief(actor.id)
      filtered_belief = if current_belief, do: BeliefGraph.filter_relevant(current_belief, relevant), else: nil
      history = load_decision_history(actor.id, 3)

      prompt = build_prompt(actor.profile, measure, current_mood, filtered_belief, history)

      responses = Enum.map(1..runs, fn run_n ->
        IO.write("  Actor #{String.slice(actor.id, 0..7)} run #{run_n}/#{runs}...")
        case ClaudeClient.complete(prompt, max_tokens: 1024) do
          {:ok, decision} ->
            case ResponseValidator.validate(decision) do
              {:ok, validated} ->
                IO.puts(" OK")
                validated
              {:error, _} ->
                IO.puts(" validation error")
                nil
            end
          {:error, _} ->
            IO.puts(" API error")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

      {actor, analyze_variance(responses)}
    end)

    IO.puts("\n=== RESULTS ===\n")

    Enum.each(results, fn {actor, stats} ->
      stratum = actor.profile["stratum"]
      orientation = actor.profile["political_orientation"]
      IO.puts("Actor #{String.slice(actor.id, 0..7)} (#{stratum}, orient=#{orientation}):")

      IO.puts("  Agreement consistency: #{stats.agreement_consistency}% (#{stats.agreement_count}/#{stats.total_runs})")
      IO.puts("  Intensity: mean=#{stats.intensity_mean} std=#{stats.intensity_std}")

      if stats.mood_stats do
        IO.puts("  Mood variance:")
        Enum.each(@mood_dimensions, fn dim ->
          s = stats.mood_stats[dim]
          if s, do: IO.puts("    #{dim}: mean=#{s.mean} std=#{s.std}")
        end)
      end

      IO.puts("")
    end)

    # Overall summary
    all_intensity_stds = Enum.map(results, fn {_, s} -> s.intensity_std end)
    avg_intensity_std = if all_intensity_stds != [], do: Float.round(Enum.sum(all_intensity_stds) / length(all_intensity_stds), 2), else: 0.0

    all_agreement = Enum.map(results, fn {_, s} -> s.agreement_consistency end)
    avg_agreement = if all_agreement != [], do: Float.round(Enum.sum(all_agreement) / length(all_agreement), 1), else: 0.0

    IO.puts("=== SUMMARY ===")
    IO.puts("Avg agreement consistency: #{avg_agreement}%")
    IO.puts("Avg intensity std: #{avg_intensity_std}")

    if avg_intensity_std > 2.0 do
      IO.puts("\n⚠ HIGH VARIANCE: Intensity std > 2.0 suggests LLM is not reasoning consistently from profile data.")
    end

    if avg_agreement < 70.0 do
      IO.puts("\n⚠ LOW AGREEMENT CONSISTENCY: < 70% suggests the LLM flips agreement randomly.")
    end
  end

  defp analyze_variance(responses) do
    total = length(responses)

    agreements = Enum.map(responses, & &1.agreement)
    true_count = Enum.count(agreements, & &1)
    majority = if true_count > total / 2, do: true_count, else: total - true_count
    agreement_consistency = if total > 0, do: Float.round(100.0 * majority / total, 1), else: 0.0

    intensities = Enum.map(responses, & &1.intensity)
    intensity_mean = if total > 0, do: Float.round(Enum.sum(intensities) / total, 1), else: 0.0
    intensity_std = std_dev(intensities)

    mood_stats = if Enum.any?(responses, & &1.mood_update != nil) do
      Enum.reduce(@mood_dimensions, %{}, fn dim, acc ->
        values = responses
        |> Enum.map(& &1.mood_update)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&(&1[dim]))
        |> Enum.reject(&is_nil/1)

        if values != [] do
          Map.put(acc, dim, %{
            mean: Float.round(Enum.sum(values) / length(values), 1),
            std: std_dev(values)
          })
        else
          acc
        end
      end)
    else
      nil
    end

    %{
      total_runs: total,
      agreement_count: true_count,
      agreement_consistency: agreement_consistency,
      intensity_mean: intensity_mean,
      intensity_std: intensity_std,
      mood_stats: mood_stats
    }
  end

  defp std_dev([]), do: 0.0
  defp std_dev(values) do
    n = length(values)
    mean = Enum.sum(values) / n
    variance = Enum.reduce(values, 0.0, fn v, acc -> acc + (v - mean) * (v - mean) end) / n
    Float.round(:math.sqrt(variance), 2)
  end

  defp load_sample(nil, sample_size) do
    Repo.all(from a in Actor, order_by: fragment("RANDOM()"), limit: ^sample_size)
  end

  defp load_sample(population_name, sample_size) do
    pop = Repo.one!(from p in "populations", where: p.name == ^population_name, select: %{id: p.id})
    Repo.all(
      from a in Actor,
        join: ap in "actor_populations", on: ap.actor_id == a.id,
        where: ap.population_id == ^pop.id,
        order_by: fragment("RANDOM()"),
        limit: ^sample_size
    )
  end

  defp load_latest_mood(actor_id) do
    Repo.one(
      from m in "actor_moods",
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1,
        select: %{
          economic_confidence: m.economic_confidence,
          government_trust: m.government_trust,
          personal_wellbeing: m.personal_wellbeing,
          social_anger: m.social_anger,
          future_outlook: m.future_outlook,
          narrative: m.narrative
        }
    )
  end

  defp load_latest_belief(actor_id) do
    result = Repo.one(
      from b in "actor_beliefs",
        where: b.actor_id == ^actor_id,
        order_by: [desc: b.inserted_at],
        limit: 1,
        select: b.graph
    )

    case result do
      nil -> nil
      graph when is_binary(graph) -> Jason.decode!(graph)
      graph when is_map(graph) -> graph
    end
  end

  defp load_decision_history(actor_id, n) do
    Repo.all(
      from d in "decisions",
        join: m in "measures", on: m.id == d.measure_id,
        where: d.actor_id == ^actor_id,
        order_by: [desc: d.inserted_at],
        limit: ^n,
        select: %{measure_title: m.title, agreement: d.agreement, intensity: d.intensity}
    )
    |> Enum.reverse()
    |> Enum.map(fn entry -> %{entry | agreement: entry.agreement == 1} end)
  end

  defp build_prompt(profile, measure, current_mood, current_belief, history) do
    cond do
      current_mood && current_belief ->
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(profile, measure, mood_context, current_belief)
      current_mood ->
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(profile, measure, mood_context)
      true ->
        PromptBuilder.build(profile, measure)
    end
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 3: Commit**

```
Add mix sim.calibrate for LLM response variance analysis
```

---

## Task 7: Repeated-Run Variance Analysis — mix sim.variance

**Files:**
- Create: `lib/mix/tasks/sim.variance.ex`

This mix task analyzes existing simulation results across measures for a population. Detects artificial consensus, emergent node bias, and belief graph divergence.

- [ ] **Step 1: Implement sim.variance**

```elixir
# lib/mix/tasks/sim.variance.ex
defmodule Mix.Tasks.Sim.Variance do
  @moduledoc """
  Analyzes simulation results for signs of LLM-generated patterns:
  - Artificial consensus (all actors converging to same opinion)
  - Emergent node bias (same concepts appearing across >50% of actors)
  - Belief graph homogenization (edge weight std decreasing over time)
  - Mood dimension clustering (actors bunching in narrow ranges)

  Usage:
    mix sim.variance --population "Panel A"
  """

  use Mix.Task

  alias PopulationSimulator.Repo
  import Ecto.Query

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      strict: [population: :string],
      aliases: [p: :population]
    )

    population_name = opts[:population] || raise "Missing --population"

    pop = Repo.one!(from p in "populations", where: p.name == ^population_name, select: %{id: p.id})
    population_id = pop.id

    IO.puts("=== VARIANCE ANALYSIS: #{population_name} ===\n")

    check_consensus(population_id)
    check_emergent_bias(population_id)
    check_mood_clustering(population_id)
    check_belief_homogenization(population_id)
  end

  defp check_consensus(population_id) do
    IO.puts("--- Consensus Detection ---")

    %{rows: rows} = Repo.query!(
      """
      SELECT
        ms.title,
        COUNT(*) as total,
        ROUND(100.0 * SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as approval_pct,
        ROUND(AVG(d.intensity), 1) as avg_intensity,
        ROUND(AVG(d.intensity * d.intensity) - AVG(d.intensity) * AVG(d.intensity), 2) as intensity_variance
      FROM decisions d
      JOIN actors a ON a.id = d.actor_id
      JOIN actor_populations ap ON ap.actor_id = a.id
      JOIN measures ms ON ms.id = d.measure_id
      WHERE ap.population_id = ?1
      GROUP BY d.measure_id, ms.title
      ORDER BY d.inserted_at
      """,
      [population_id]
    )

    Enum.each(rows, fn [title, total, approval, avg_int, int_var] ->
      warnings = []
      warnings = if approval > 90.0 or approval < 10.0, do: ["EXTREME CONSENSUS" | warnings], else: warnings
      warnings = if int_var != nil and int_var < 1.5, do: ["LOW VARIANCE" | warnings], else: warnings

      flag = if warnings != [], do: " ⚠ #{Enum.join(warnings, ", ")}", else: ""
      IO.puts("  #{title}: #{approval}% approval, avg_intensity=#{avg_int}, var=#{int_var || "?"} (n=#{total})#{flag}")
    end)

    IO.puts("")
  end

  defp check_emergent_bias(population_id) do
    IO.puts("--- Emergent Node Bias ---")

    total_actors = Repo.one!(
      from ap in "actor_populations",
        where: ap.population_id == ^population_id,
        select: count(ap.actor_id)
    )

    %{rows: rows} = Repo.query!(
      """
      SELECT
        jn.value ->> '$.id' as node_id,
        jn.value ->> '$.added_at' as added_at,
        COUNT(DISTINCT ab.actor_id) as actor_count
      FROM actor_beliefs ab
      JOIN (
        SELECT actor_id, MAX(inserted_at) as max_ts
        FROM actor_beliefs
        GROUP BY actor_id
      ) latest ON latest.actor_id = ab.actor_id AND latest.max_ts = ab.inserted_at
      JOIN actor_populations ap ON ap.actor_id = ab.actor_id
      , json_each(ab.graph, '$.nodes') jn
      WHERE ap.population_id = ?1
        AND jn.value ->> '$.type' = 'emergent'
      GROUP BY node_id, added_at
      ORDER BY actor_count DESC
      """,
      [population_id]
    )

    if rows == [] do
      IO.puts("  No emergent nodes found.")
    else
      Enum.each(rows, fn [node_id, added_at, count] ->
        pct = Float.round(100.0 * count / max(total_actors, 1), 1)
        flag = if pct > 50.0, do: " ⚠ MODEL BIAS (>50% actors share this concept)", else: ""
        IO.puts("  #{node_id} (from: #{added_at}): #{count}/#{total_actors} actors (#{pct}%)#{flag}")
      end)
    end

    IO.puts("")
  end

  defp check_mood_clustering(population_id) do
    IO.puts("--- Mood Clustering ---")

    %{rows: rows} = Repo.query!(
      """
      SELECT
        ms.title,
        ROUND(AVG(m.economic_confidence), 1) as ec_mean,
        ROUND(AVG(m.economic_confidence * m.economic_confidence) - AVG(m.economic_confidence) * AVG(m.economic_confidence), 2) as ec_var,
        ROUND(AVG(m.government_trust), 1) as gt_mean,
        ROUND(AVG(m.government_trust * m.government_trust) - AVG(m.government_trust) * AVG(m.government_trust), 2) as gt_var,
        ROUND(AVG(m.social_anger), 1) as sa_mean,
        ROUND(AVG(m.social_anger * m.social_anger) - AVG(m.social_anger) * AVG(m.social_anger), 2) as sa_var
      FROM actor_moods m
      JOIN measures ms ON ms.id = m.measure_id
      JOIN actor_populations ap ON ap.actor_id = m.actor_id
      WHERE ap.population_id = ?1 AND m.measure_id IS NOT NULL
      GROUP BY m.measure_id, ms.title
      ORDER BY m.inserted_at
      """,
      [population_id]
    )

    Enum.each(rows, fn [title, ec_m, ec_v, gt_m, gt_v, sa_m, sa_v] ->
      dims = [{"economic_confidence", ec_m, ec_v}, {"government_trust", gt_m, gt_v}, {"social_anger", sa_m, sa_v}]
      low_var = Enum.filter(dims, fn {_, _, v} -> v != nil and v < 1.0 end)

      flag = if length(low_var) >= 2, do: " ⚠ MOOD CLUSTERING", else: ""
      IO.puts("  #{title}:#{flag}")

      Enum.each(dims, fn {name, mean, var} ->
        dim_flag = if var != nil and var < 1.0, do: " ⚠", else: ""
        IO.puts("    #{name}: mean=#{mean} var=#{var || "?"}#{dim_flag}")
      end)
    end)

    IO.puts("")
  end

  defp check_belief_homogenization(population_id) do
    IO.puts("--- Belief Homogenization ---")

    %{rows: rows} = Repo.query!(
      """
      SELECT
        ms.title,
        je.value ->> '$.from' as edge_from,
        je.value ->> '$.to' as edge_to,
        ROUND(AVG(CAST(je.value ->> '$.weight' AS REAL)), 2) as avg_weight,
        ROUND(AVG(CAST(je.value ->> '$.weight' AS REAL) * CAST(je.value ->> '$.weight' AS REAL))
              - AVG(CAST(je.value ->> '$.weight' AS REAL)) * AVG(CAST(je.value ->> '$.weight' AS REAL)), 3) as weight_var,
        COUNT(DISTINCT ab.actor_id) as n
      FROM actor_beliefs ab
      JOIN measures ms ON ms.id = ab.measure_id
      JOIN actor_populations ap ON ap.actor_id = ab.actor_id
      , json_each(ab.graph, '$.edges') je
      WHERE ap.population_id = ?1 AND ab.measure_id IS NOT NULL
      GROUP BY ms.title, edge_from, edge_to
      HAVING n >= 10
      ORDER BY ab.inserted_at, weight_var ASC
      LIMIT 20
      """,
      [population_id]
    )

    if rows == [] do
      IO.puts("  Not enough data for homogenization analysis.")
    else
      Enum.each(rows, fn [title, from, to, avg_w, var, n] ->
        flag = if var != nil and var < 0.01, do: " ⚠ HOMOGENIZED", else: ""
        IO.puts("  #{title} | #{from}->#{to}: avg=#{avg_w} var=#{var || "?"} (n=#{n})#{flag}")
      end)
    end

    IO.puts("")
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 3: Commit**

```
Add mix sim.variance for detecting artificial consensus and emergent bias
```

---

## Task 8: Update CLAUDE.md with new commands and architecture

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add new modules and commands to CLAUDE.md**

Add to the **Core Modules** table:

```
| `ResponseValidator` | Schema validation + rule constraints for LLM responses (pre-persistence) |
| `ConsistencyChecker` | Demographic consistency checks: stratum/orientation vs mood/intensity |
```

Add to the **Commands** section:

```bash
# Calibration & Variance
mix sim.calibrate --measure-id <id> --runs 5 --sample 10
mix sim.variance --population "Panel A"
```

Add a new section after **Key design decisions**:

```
### LLM Grounding Controls (5 layers)

1. **Rule constraints**: ResponseValidator enforces schema (types, ranges, lengths), caps intensity 1-10, limits belief deltas (max 3 nodes, 5 edges per measure), validates node IDs (snake_case, max 30 chars).
2. **Bounded belief updates**: BeliefGraph caps emergent nodes at 10, total edges at 40, dampens edge weight changes (max 0.4 per measure), decays unreinforced emergent nodes after 3 measures.
3. **Calibration loops**: `mix sim.calibrate` runs same measure N times for sample actors without persisting — reports agreement consistency and per-dimension variance. High variance = LLM hallucinating.
4. **Consistency checks**: ConsistencyChecker applies demographic rules post-response (e.g., destitute + austerity → cap economic_confidence, floor social_anger; opposing orientation → cap intensity).
5. **Variance analysis**: `mix sim.variance` analyzes persisted results for artificial consensus (>90% agreement), emergent node bias (>50% actors share concept), mood clustering (low dimension variance), belief homogenization.
```

- [ ] **Step 2: Commit**

```
Document LLM grounding controls in CLAUDE.md
```
