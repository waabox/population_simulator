# Layer 5: Theory of Mind — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After each café, actors form a perception of their group's mood (computed) and identify 1-2 referents who influenced them (from LLM output). These perceptions are injected into future prompts.

**Architecture:** TheoryOfMindBuilder computes group mood stats from café data and persists referents from the café LLM response. CafePromptBuilder is extended to request referents in output. ConsciousnessLoader loads perceptions for prompt injection. No extra LLM calls — referents come from the existing café response.

**Tech Stack:** Elixir/Ecto, SQLite3.

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `priv/repo/migrations/20260403500000_create_actor_perceptions.exs` | actor_perceptions table |
| `lib/population_simulator/simulation/actor_perception.ex` | Ecto schema |
| `lib/population_simulator/simulation/theory_of_mind_builder.ex` | Compute group mood + persist referents |

### Modified files

| File | Change |
|------|--------|
| `lib/population_simulator/simulation/cafe_prompt_builder.ex` | Request referents in LLM output |
| `lib/population_simulator/simulation/cafe_response_validator.ex` | Validate referents array |
| `lib/population_simulator/simulation/cafe_runner.ex` | Call TheoryOfMindBuilder after café |
| `lib/population_simulator/simulation/consciousness_loader.ex` | Load perceptions for prompt |
| `lib/population_simulator/simulation/prompt_builder.ex` | Add perceptions block |

---

## Task 1: Migration + Schema

**Files:**
- Create: `priv/repo/migrations/20260403500000_create_actor_perceptions.exs`
- Create: `lib/population_simulator/simulation/actor_perception.ex`

- [ ] **Step 1: Create migration**

```elixir
# priv/repo/migrations/20260403500000_create_actor_perceptions.exs
defmodule PopulationSimulator.Repo.Migrations.CreateActorPerceptions do
  use Ecto.Migration

  def change do
    create table(:actor_perceptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :cafe_session_id, references(:cafe_sessions, type: :binary_id, on_delete: :delete_all), null: false
      add :group_mood, :text, null: false
      add :referent_id, references(:actors, type: :binary_id, on_delete: :nilify_all)
      add :referent_influence, :text
      timestamps(type: :utc_datetime)
    end

    create index(:actor_perceptions, [:actor_id])
    create index(:actor_perceptions, [:actor_id, :measure_id])
  end
end
```

- [ ] **Step 2: Create ActorPerception schema**

```elixir
# lib/population_simulator/simulation/actor_perception.ex
defmodule PopulationSimulator.Simulation.ActorPerception do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_perceptions" do
    belongs_to :actor, PopulationSimulator.Actors.Actor
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    belongs_to :cafe_session, PopulationSimulator.Simulation.CafeSession
    belongs_to :referent, PopulationSimulator.Actors.Actor
    field :group_mood, :string
    field :referent_influence, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(perception, attrs) do
    perception
    |> cast(attrs, [:actor_id, :measure_id, :cafe_session_id, :group_mood, :referent_id, :referent_influence])
    |> validate_required([:actor_id, :measure_id, :cafe_session_id, :group_mood])
  end

  def new(actor_id, measure_id, cafe_session_id, group_mood, referent_id, referent_influence) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      cafe_session_id: cafe_session_id,
      group_mood: Jason.encode!(group_mood),
      referent_id: referent_id,
      referent_influence: referent_influence,
      inserted_at: now,
      updated_at: now
    }
  end
end
```

- [ ] **Step 3: Run migration and tests**

Run: `mix ecto.migrate && mix test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/20260403500000_create_actor_perceptions.exs lib/population_simulator/simulation/actor_perception.ex
git commit -m "Add actor_perceptions table and ActorPerception schema"
```

---

## Task 2: TheoryOfMindBuilder

**Files:**
- Create: `lib/population_simulator/simulation/theory_of_mind_builder.ex`

- [ ] **Step 1: Implement TheoryOfMindBuilder**

```elixir
# lib/population_simulator/simulation/theory_of_mind_builder.ex
defmodule PopulationSimulator.Simulation.TheoryOfMindBuilder do
  @moduledoc """
  Computes group mood perception and persists referent data from café output.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorPerception

  @mood_labels [
    {7, "esperanzados"},
    {6, "cautelosamente optimistas"},
    {5, "indiferentes"},
    {4, "preocupados"},
    {3, "frustrados"},
    {0, "enojados"}
  ]

  def process_cafe(cafe_session_id, measure_id, table_actors, validated_response) do
    group_mood = compute_group_mood(table_actors, validated_response)
    referents = extract_referents(validated_response)

    actor_ids = Enum.map(table_actors, & &1.actor_id)

    Enum.each(actor_ids, fn actor_id ->
      # Find referent for this actor (if any)
      referent = Enum.find(referents, fn r -> r["perceived_by"] == actor_id end)

      referent_id = if referent, do: referent["actor_id"], else: nil
      referent_influence = if referent, do: referent["influence"], else: nil

      # Only persist if referent_id is in the table (valid actor)
      valid_referent_id = if referent_id in actor_ids, do: referent_id, else: nil

      row = ActorPerception.new(
        actor_id,
        measure_id,
        cafe_session_id,
        group_mood,
        valid_referent_id,
        referent_influence
      )

      Repo.insert_all(ActorPerception, [row])
    end)
  end

  defp compute_group_mood(table_actors, validated) do
    effects = validated["effects"] || []

    # Agreement ratio from original decisions
    approved = Enum.count(table_actors, fn a -> a.decision.agreement end)
    total = length(table_actors)
    agreement_ratio = if total > 0, do: Float.round(approved / total, 2), else: 0.0

    # Average social anger from moods
    avg_anger =
      table_actors
      |> Enum.map(fn a -> a.mood.social_anger end)
      |> then(fn vals -> Enum.sum(vals) / max(length(vals), 1) end)

    mood_label = label_for_anger(avg_anger)

    # Dominant emotion from effects
    dominant = dominant_emotion(effects)

    %{
      mood: mood_label,
      agreement_ratio: agreement_ratio,
      dominant_emotion: dominant
    }
  end

  defp label_for_anger(avg) do
    @mood_labels
    |> Enum.find(fn {threshold, _} -> avg >= threshold end)
    |> case do
      {_, label} -> label
      nil -> "neutros"
    end
  end

  defp dominant_emotion(effects) do
    effects
    |> Enum.flat_map(fn e ->
      (e["mood_deltas"] || %{})
      |> Enum.map(fn {dim, val} -> {dim, abs(val)} end)
    end)
    |> Enum.group_by(fn {dim, _} -> dim end, fn {_, val} -> val end)
    |> Enum.map(fn {dim, vals} -> {dim, Enum.sum(vals)} end)
    |> Enum.max_by(fn {_, total} -> total end, fn -> {"social_anger", 0} end)
    |> elem(0)
  end

  defp extract_referents(validated) do
    validated["referents"] || []
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/theory_of_mind_builder.ex
git commit -m "Add TheoryOfMindBuilder for group mood and referent perception"
```

---

## Task 3: Café modifications (prompt + validator + runner)

**Files:**
- Modify: `lib/population_simulator/simulation/cafe_prompt_builder.ex`
- Modify: `lib/population_simulator/simulation/cafe_response_validator.ex`
- Modify: `lib/population_simulator/simulation/cafe_runner.ex`

- [ ] **Step 1: Add referents request to CafePromptBuilder**

Read `cafe_prompt_builder.ex`. In the JSON output format section of the prompt, after the `"effects"` block, add:

```
      "referents": [
        {
          "actor_id": "<uuid del actor que influenció>",
          "perceived_by": "<uuid del actor que fue influenciado>",
          "influence": "<qué le hizo pensar/sentir>",
          "influence_type": "positive" o "negative"
        }
      ]
```

And in the REGLAS section, add:
```
    - referents: máximo 2 por participante. Identificá quién influyó más a quién durante la conversación. Un actor no puede ser referente de sí mismo.
```

- [ ] **Step 2: Add referents validation to CafeResponseValidator**

Read `cafe_response_validator.ex`. The validate function should also process the `referents` field. After validating effects, add:

```elixir
      |> Map.update("referents", [], &validate_referents(&1, actor_ids))
```

Add helper:
```elixir
  defp validate_referents(referents, actor_ids) when is_list(referents) do
    referents
    |> Enum.filter(fn r ->
      is_map(r) and
        r["actor_id"] in actor_ids and
        r["perceived_by"] in actor_ids and
        r["actor_id"] != r["perceived_by"]
    end)
    |> Enum.group_by(fn r -> r["perceived_by"] end)
    |> Enum.flat_map(fn {_, refs} -> Enum.take(refs, 2) end)
  end

  defp validate_referents(_, _), do: []
```

- [ ] **Step 3: Wire TheoryOfMindBuilder into CafeRunner**

Read `cafe_runner.ex`. After `persist_cafe/6` and `AffinityTracker.update_from_cafe/1`, add:

```elixir
      alias PopulationSimulator.Simulation.TheoryOfMindBuilder

      TheoryOfMindBuilder.process_cafe(session_row.id, measure.id, table_actors, validated)
```

- [ ] **Step 4: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/cafe_prompt_builder.ex lib/population_simulator/simulation/cafe_response_validator.ex lib/population_simulator/simulation/cafe_runner.ex
git commit -m "Request and validate referents in café, wire TheoryOfMindBuilder"
```

---

## Task 4: Prompt injection

**Files:**
- Modify: `lib/population_simulator/simulation/consciousness_loader.ex`
- Modify: `lib/population_simulator/simulation/prompt_builder.ex`

- [ ] **Step 1: Load perceptions in ConsciousnessLoader**

Read `consciousness_loader.ex`. Add a function to load recent perceptions and include them in the `load/1` return map:

```elixir
  defp load_recent_perceptions(actor_id, limit \\ 2) do
    import Ecto.Query

    Repo.all(
      from(p in PopulationSimulator.Simulation.ActorPerception,
        left_join: a in PopulationSimulator.Actors.Actor, on: a.id == p.referent_id,
        where: p.actor_id == ^actor_id,
        order_by: [desc: p.inserted_at],
        limit: ^limit,
        select: %{
          group_mood: p.group_mood,
          referent_influence: p.referent_influence
        }
      )
    )
    |> Enum.reverse()
  end
```

Add `perceptions: load_recent_perceptions(actor_id)` to the returned map in `load/1`.

- [ ] **Step 2: Add perceptions block to PromptBuilder**

In `prompt_builder.ex`, in `build_consciousness_block/1`, add:

```elixir
    perceptions_text =
      case consciousness[:perceptions] do
        nil -> ""
        [] -> ""
        perceptions ->
          items = Enum.map_join(perceptions, "\n", fn p ->
            group = Jason.decode!(p.group_mood)
            base = "En tu grupo, el ánimo general era de #{group["mood"]} (#{round(group["agreement_ratio"] * 100)}% aprobó la medida)."
            ref = if p.referent_influence, do: " #{p.referent_influence}", else: ""
            "- #{base}#{ref}"
          end)
          "\n\n=== LO QUE PERCIBÍS DE TU ENTORNO ===\n#{items}"
      end
```

Append `#{perceptions_text}` to the consciousness block.

- [ ] **Step 3: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator/simulation/consciousness_loader.ex lib/population_simulator/simulation/prompt_builder.ex
git commit -m "Inject social perceptions into actor prompts"
```

---

## Task 5: CLAUDE.md docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add theory of mind documentation**

After the social bonds bullet:

```markdown
- **Theory of mind**: After each café, TheoryOfMindBuilder computes group mood perception (agreement ratio + dominant emotion, no LLM) and extracts referents (1-2 per actor) from the café LLM response. Perceptions are persisted in actor_perceptions and injected into future prompts so actors reason about their social environment.
```

In Core Modules table:
```markdown
| `TheoryOfMindBuilder` | Group mood computation, referent extraction and persistence |
```

In Database Schema:
```markdown
- **actor_perceptions** — group mood perception + referent influence per actor per café
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document theory of mind in CLAUDE.md"
```
