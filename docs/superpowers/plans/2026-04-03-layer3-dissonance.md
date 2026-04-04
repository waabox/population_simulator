# Layer 3: Cognitive Dissonance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cognitive dissonance index that measures contradiction between an actor's mood/beliefs/history and their decisions, producing immediate volatility (higher LLM temperature) and confrontation during introspection.

**Architecture:** DissonanceCalculator is a pure-math module that computes a 0-1 dissonance index per decision. The index is stored in a new `dissonance` column on `decisions`. MeasureRunner passes per-actor temperature to ClaudeClient based on dissonance. IntrospectionPromptBuilder includes dissonance confrontation when accumulated dissonance is high. No new LLM calls — this is entirely computational + prompt modification.

**Tech Stack:** Elixir/Ecto, SQLite3, existing simulation modules.

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `priv/repo/migrations/20260403200000_add_dissonance_to_decisions.exs` | Add dissonance column |
| `lib/population_simulator/simulation/dissonance_calculator.ex` | Compute dissonance index |
| `test/population_simulator/simulation/dissonance_calculator_test.exs` | Unit tests |

### Modified files

| File | Change |
|------|--------|
| `lib/population_simulator/simulation/decision.ex` | Add `:dissonance` field to schema + changeset |
| `lib/population_simulator/simulation/measure_runner.ex` | Compute dissonance post-decision, pass per-actor temperature |
| `lib/population_simulator/simulation/introspection_prompt_builder.ex` | Add dissonance confrontation block |
| `lib/population_simulator/simulation/consciousness_loader.ex` | Load recent dissonance values |

---

## Task 1: Migration + Schema

**Files:**
- Create: `priv/repo/migrations/20260403200000_add_dissonance_to_decisions.exs`
- Modify: `lib/population_simulator/simulation/decision.ex`

- [ ] **Step 1: Create migration**

```elixir
# priv/repo/migrations/20260403200000_add_dissonance_to_decisions.exs
defmodule PopulationSimulator.Repo.Migrations.AddDissonanceToDecisions do
  use Ecto.Migration

  def change do
    alter table(:decisions) do
      add :dissonance, :float
    end
  end
end
```

- [ ] **Step 2: Add field to Decision schema**

In `lib/population_simulator/simulation/decision.ex`, add to the schema block after `field :tokens_used, :integer`:

```elixir
    field :dissonance, :float
```

And add `:dissonance` to the cast list in the changeset function.

- [ ] **Step 3: Run migration and tests**

Run: `mix ecto.migrate && mix test`
Expected: Migration applies, all existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/20260403200000_add_dissonance_to_decisions.exs lib/population_simulator/simulation/decision.ex
git commit -m "Add dissonance column to decisions table"
```

---

## Task 2: DissonanceCalculator

**Files:**
- Create: `test/population_simulator/simulation/dissonance_calculator_test.exs`
- Create: `lib/population_simulator/simulation/dissonance_calculator.ex`

- [ ] **Step 1: Write failing tests**

```elixir
# test/population_simulator/simulation/dissonance_calculator_test.exs
defmodule PopulationSimulator.Simulation.DissonanceCalculatorTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.DissonanceCalculator

  describe "compute/3" do
    test "high social_anger + agreement = high dissonance" do
      mood = %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 9, future_outlook: 5}
      decision = %{agreement: true, intensity: 6}
      history = []

      result = DissonanceCalculator.compute(mood, decision, history)

      assert result >= 0.7
      assert result <= 1.0
    end

    test "low government_trust + agreement = dissonance" do
      mood = %{economic_confidence: 5, government_trust: 2, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: true, intensity: 5}
      history = []

      result = DissonanceCalculator.compute(mood, decision, history)

      assert result >= 0.5
    end

    test "high economic_confidence + rejection = dissonance" do
      mood = %{economic_confidence: 9, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: false, intensity: 5}
      history = []

      result = DissonanceCalculator.compute(mood, decision, history)

      assert result >= 0.7
    end

    test "consistent mood + decision = low dissonance" do
      mood = %{economic_confidence: 3, government_trust: 3, personal_wellbeing: 3, social_anger: 8, future_outlook: 3}
      decision = %{agreement: false, intensity: 7}
      history = []

      result = DissonanceCalculator.compute(mood, decision, history)

      assert result <= 0.1
    end

    test "history contradiction adds dissonance" do
      mood = %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: true, intensity: 5}
      history = [
        %{agreement: false, intensity: 6},
        %{agreement: false, intensity: 7},
        %{agreement: false, intensity: 5}
      ]

      result = DissonanceCalculator.compute(mood, decision, history)

      assert result >= 0.4
    end

    test "two opposing history entries = moderate dissonance" do
      mood = %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: true, intensity: 5}
      history = [
        %{agreement: true, intensity: 5},
        %{agreement: false, intensity: 6},
        %{agreement: false, intensity: 7}
      ]

      result = DissonanceCalculator.compute(mood, decision, history)

      assert result >= 0.2
      assert result <= 0.4
    end

    test "result is always clamped between 0 and 1" do
      mood = %{economic_confidence: 10, government_trust: 1, personal_wellbeing: 1, social_anger: 10, future_outlook: 1}
      decision = %{agreement: true, intensity: 10}
      history = [
        %{agreement: false, intensity: 10},
        %{agreement: false, intensity: 10},
        %{agreement: false, intensity: 10}
      ]

      result = DissonanceCalculator.compute(mood, decision, history)

      assert result >= 0.0
      assert result <= 1.0
    end
  end

  describe "temperature_for/1" do
    test "zero dissonance = base temperature 0.3" do
      assert DissonanceCalculator.temperature_for(0.0) == 0.3
    end

    test "max dissonance = temperature 0.7" do
      assert DissonanceCalculator.temperature_for(1.0) == 0.7
    end

    test "mid dissonance = proportional temperature" do
      result = DissonanceCalculator.temperature_for(0.5)
      assert_in_delta result, 0.5, 0.01
    end
  end

  describe "should_confront?/1" do
    test "returns true when average dissonance > 0.4" do
      recent = [0.6, 0.5, 0.3]
      assert DissonanceCalculator.should_confront?(recent) == true
    end

    test "returns false when average dissonance <= 0.4" do
      recent = [0.3, 0.2, 0.1]
      assert DissonanceCalculator.should_confront?(recent) == false
    end

    test "returns false for empty list" do
      assert DissonanceCalculator.should_confront?([]) == false
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/dissonance_calculator_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement DissonanceCalculator**

```elixir
# lib/population_simulator/simulation/dissonance_calculator.ex
defmodule PopulationSimulator.Simulation.DissonanceCalculator do
  @moduledoc """
  Computes cognitive dissonance index (0-1) by comparing an actor's
  mood, beliefs, and decision history against their current decision.
  High dissonance increases LLM temperature (volatility) and triggers
  confrontation during introspection.
  """

  @base_temperature 0.3
  @max_temperature 0.7
  @confrontation_threshold 0.4

  def compute(mood, decision, history) do
    mood_d = mood_dissonance(mood, decision.agreement)
    history_d = history_dissonance(decision.agreement, history)

    (mood_d + history_d)
    |> max(0.0)
    |> min(1.0)
  end

  def temperature_for(dissonance) when is_number(dissonance) do
    Float.round(@base_temperature + dissonance * (@max_temperature - @base_temperature), 2)
  end

  def temperature_for(_), do: @base_temperature

  def should_confront?(recent_dissonances) when is_list(recent_dissonances) do
    case recent_dissonances do
      [] -> false
      values ->
        avg = Enum.sum(values) / length(values)
        avg > @confrontation_threshold
    end
  end

  def accumulated_anger_bump(recent_dissonances) do
    consecutive_high =
      recent_dissonances
      |> Enum.take(3)
      |> Enum.count(&(&1 > 0.5))

    if consecutive_high >= 3, do: 0.5, else: 0.0
  end

  defp mood_dissonance(mood, agreement) do
    cond do
      agreement and mood.social_anger > 7 ->
        (mood.social_anger - 5) / 5

      agreement and mood.government_trust < 3 ->
        (5 - mood.government_trust) / 5

      not agreement and mood.economic_confidence > 7 ->
        (mood.economic_confidence - 5) / 5

      true ->
        0.0
    end
  end

  defp history_dissonance(current_agreement, history) do
    opposite_count =
      history
      |> Enum.count(fn h -> h.agreement != current_agreement end)

    cond do
      opposite_count >= 3 -> 0.5
      opposite_count >= 2 -> 0.3
      true -> 0.0
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/population_simulator/simulation/dissonance_calculator_test.exs`
Expected: All pass.

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/population_simulator/simulation/dissonance_calculator.ex test/population_simulator/simulation/dissonance_calculator_test.exs
git commit -m "Add DissonanceCalculator with mood/history dissonance and temperature scaling"
```

---

## Task 3: MeasureRunner integration

**Files:**
- Modify: `lib/population_simulator/simulation/measure_runner.ex`

- [ ] **Step 1: Read measure_runner.ex to understand current structure**

Read the file, focusing on:
- `evaluate_actor/5` function (lines ~109-192)
- Where `ClaudeClient.complete` is called (line ~128)
- Where the decision is persisted (lines ~140-170)
- The `load_decision_history/2` function (lines ~320-338)

- [ ] **Step 2: Add per-actor temperature based on dissonance**

In `evaluate_actor`, before the `ClaudeClient.complete` call, load recent dissonance values and compute temperature:

```elixir
      # After building the prompt, before ClaudeClient call:
      recent_dissonances = load_recent_dissonances(actor.id, 3)
      latest_dissonance = List.first(recent_dissonances) || 0.0
      temperature = DissonanceCalculator.temperature_for(latest_dissonance)
```

Then modify the ClaudeClient call to pass temperature:

```elixir
      case ClaudeClient.complete(prompt, max_tokens: 1024, temperature: temperature) do
```

Add the alias at the top of the module:
```elixir
alias PopulationSimulator.Simulation.DissonanceCalculator
```

- [ ] **Step 3: Compute and persist dissonance after each decision**

After the decision is validated and before persistence, compute dissonance:

```elixir
      dissonance = DissonanceCalculator.compute(current_mood_map, validated, history)
```

Where `current_mood_map` is the mood struct used for the prompt, and `validated` is the validated decision (has `.agreement`). Add the dissonance to the decision row being persisted:

In the decision insert map, add:
```elixir
      dissonance: dissonance,
```

- [ ] **Step 4: Apply accumulated anger bump**

After computing dissonance, check for accumulated anger:

```elixir
      anger_bump = DissonanceCalculator.accumulated_anger_bump([dissonance | recent_dissonances])
      # If anger_bump > 0, apply it to the mood that gets persisted
```

If `anger_bump > 0` and there's a mood update being persisted, add it to `social_anger` (clamped to 10).

- [ ] **Step 5: Add helper function to load recent dissonances**

Add to measure_runner.ex:

```elixir
  defp load_recent_dissonances(actor_id, limit) do
    import Ecto.Query

    Repo.all(
      from(d in Decision,
        where: d.actor_id == ^actor_id and not is_nil(d.dissonance),
        order_by: [desc: d.inserted_at],
        limit: ^limit,
        select: d.dissonance
      )
    )
  end
```

- [ ] **Step 6: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass. No existing behavior changed — dissonance is nil for old decisions, temperature defaults to 0.3.

- [ ] **Step 7: Commit**

```bash
git add lib/population_simulator/simulation/measure_runner.ex
git commit -m "Integrate dissonance into MeasureRunner: per-actor temperature and anger accumulation"
```

---

## Task 4: Introspection confrontation

**Files:**
- Modify: `lib/population_simulator/simulation/introspection_prompt_builder.ex`
- Modify: `lib/population_simulator/simulation/consciousness_loader.ex`

- [ ] **Step 1: Extend ConsciousnessLoader to load dissonance data**

Read `lib/population_simulator/simulation/consciousness_loader.ex`. Add a function to load recent dissonances and any confrontation-worthy contradictions.

Add to the `load/1` function's return map:

```elixir
  def load(actor_id) do
    summary = load_latest_summary(actor_id)
    cafe_summaries = load_recent_cafe_summaries(actor_id, 2)
    dissonance_data = load_dissonance_data(actor_id)

    case summary do
      nil ->
        if dissonance_data do
          %{narrative: nil, self_observations: [], cafe_summaries: cafe_summaries, dissonance: dissonance_data}
        else
          nil
        end
      _ ->
        %{
          narrative: summary.narrative,
          self_observations: Jason.decode!(summary.self_observations),
          cafe_summaries: cafe_summaries,
          dissonance: dissonance_data
        }
    end
  end

  defp load_dissonance_data(actor_id) do
    recent = Repo.all(
      from(d in PopulationSimulator.Simulation.Decision,
        where: d.actor_id == ^actor_id and not is_nil(d.dissonance),
        order_by: [desc: d.inserted_at],
        limit: 3,
        select: {d.dissonance, d.agreement, d.reasoning}
      )
    )

    case recent do
      [] -> nil
      values ->
        dissonances = Enum.map(values, fn {d, _, _} -> d end)
        should_confront = PopulationSimulator.Simulation.DissonanceCalculator.should_confront?(dissonances)

        contradictions =
          if should_confront do
            values
            |> Enum.filter(fn {d, _, _} -> d > 0.4 end)
            |> Enum.map(fn {_d, agreement, reasoning} ->
              action = if agreement, do: "aprobaste", else: "rechazaste"
              "#{action}: #{reasoning}"
            end)
          else
            []
          end

        %{recent_values: dissonances, should_confront: should_confront, contradictions: contradictions}
    end
  end
```

- [ ] **Step 2: Add dissonance confrontation to IntrospectionPromptBuilder**

Read `lib/population_simulator/simulation/introspection_prompt_builder.ex`. The `build/5` function receives (profile, previous_narrative, decisions, cafe_summaries, current_mood). It needs a 6th parameter for dissonance data.

Add a new `build/6` that wraps `build/5`:

```elixir
  def build(profile, previous_narrative, decisions, cafe_summaries, current_mood, dissonance_data) do
    base = build(profile, previous_narrative, decisions, cafe_summaries, current_mood)

    dissonance_block = build_dissonance_block(dissonance_data)

    if dissonance_block != "" do
      String.replace(base, "=== INSTRUCCIONES ===", "#{dissonance_block}\n=== INSTRUCCIONES ===")
    else
      base
    end
  end

  defp build_dissonance_block(nil), do: ""
  defp build_dissonance_block(%{should_confront: false}), do: ""

  defp build_dissonance_block(%{should_confront: true, contradictions: contradictions}) do
    items = Enum.map_join(contradictions, "\n", fn c -> "- #{c}" end)

    """
    === CONTRADICCIONES DETECTADAS ===
    Se detectaron contradicciones entre tu estado de ánimo y tus decisiones recientes:
    #{items}
    Reflexioná sobre estas contradicciones: ¿cambiaste de opinión, o hay algo que no estás reconociendo?
    """
  end
```

- [ ] **Step 3: Update IntrospectionRunner to pass dissonance data**

Read `lib/population_simulator/simulation/introspection_runner.ex`. In the `introspect_actor/2` function, load dissonance data and call `build/6` instead of `build/5`:

```elixir
    dissonance_data = PopulationSimulator.Simulation.ConsciousnessLoader.load_dissonance_data(actor.id)

    prompt = IntrospectionPromptBuilder.build(
      actor.profile,
      previous_narrative,
      decisions,
      cafe_summaries,
      current_mood,
      dissonance_data
    )
```

Note: `load_dissonance_data` needs to be made public in ConsciousnessLoader (change `defp` to `def`).

- [ ] **Step 4: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass. Introspection gracefully handles nil dissonance data (build/5 still works as fallback).

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/consciousness_loader.ex lib/population_simulator/simulation/introspection_prompt_builder.ex lib/population_simulator/simulation/introspection_runner.ex
git commit -m "Add dissonance confrontation to introspection and consciousness loader"
```

---

## Task 5: Mix task + CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add dissonance documentation to CLAUDE.md**

In the "Key design decisions" section, after the consciousness bullet, add:

```markdown
- **Cognitive dissonance**: DissonanceCalculator computes a 0-1 index per decision by comparing mood (anger/trust/confidence) and history against the decision. High dissonance raises LLM temperature (0.3 → up to 0.7) for that actor, making responses more volatile. Accumulated dissonance (>0.5 for 3+ measures) auto-increments social_anger. IntrospectionPromptBuilder confronts actors with their contradictions every 3 measures.
```

In the Core Modules table, add:

```markdown
| `DissonanceCalculator` | Cognitive dissonance index, temperature scaling, confrontation triggers |
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document cognitive dissonance in CLAUDE.md"
```

---

## Task 6: Smoke test

- [ ] **Step 1: Run existing simulation and verify dissonance is computed**

```bash
sqlite3 population_simulator_dev.db "SELECT COUNT(*), ROUND(AVG(dissonance), 3), ROUND(MAX(dissonance), 3) FROM decisions WHERE dissonance IS NOT NULL"
```

If no recent simulation, run a quick one:
```bash
export CLAUDE_API_KEY=<key>
mix sim.run --title "Test dissonance" --description "El gobierno sube el IVA del 21% al 25%." --population "1000 personas" --concurrency 30
```

Then verify:
```bash
sqlite3 population_simulator_dev.db "
SELECT 
  CASE 
    WHEN dissonance IS NULL THEN 'null'
    WHEN dissonance < 0.2 THEN 'low (0-0.2)'
    WHEN dissonance < 0.5 THEN 'medium (0.2-0.5)'
    ELSE 'high (0.5+)'
  END as level,
  COUNT(*) as n
FROM decisions 
WHERE measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
GROUP BY level
ORDER BY level"
```

Expected: Mix of low/medium/high dissonance. Not all zeros. Not all high.

- [ ] **Step 2: Verify temperature variation in logs**

Check that actors with high dissonance get higher temperature. Look at the LLM responses — actors with dissonance > 0.5 should show more varied/unexpected decisions.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "Fix issues found during dissonance smoke test"
```
