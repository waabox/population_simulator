# Actor Consciousness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add autobiographical memory, social interaction (mesa de café), and periodic metacognition to simulated actors.

**Architecture:** Three new runners (CafeRunner, IntrospectionRunner) plug into the existing MeasureRunner flow. CafeRunner groups actors by zone+stratum affinity into tables of 5-7, dispatches one LLM call per table, and persists full dialogues + mood/belief effects. IntrospectionRunner fires every 3 measures to generate evolving autobiographical narratives. PromptBuilder gains arity 5 to inject consciousness context.

**Tech Stack:** Elixir/OTP, Ecto/SQLite3, Claude API (Haiku), existing grounding layers (ResponseValidator, ConsistencyChecker, BeliefGraph).

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `priv/repo/migrations/20260403100000_create_cafe_sessions.exs` | cafe_sessions + cafe_effects tables |
| `priv/repo/migrations/20260403100001_create_actor_summaries.exs` | actor_summaries table |
| `lib/population_simulator/simulation/cafe_session.ex` | Ecto schema for cafe_sessions |
| `lib/population_simulator/simulation/cafe_effect.ex` | Ecto schema for cafe_effects |
| `lib/population_simulator/simulation/actor_summary.ex` | Ecto schema for actor_summaries |
| `lib/population_simulator/simulation/cafe_grouper.ex` | Groups actors into tables by zone+stratum |
| `lib/population_simulator/simulation/cafe_prompt_builder.ex` | Builds group conversation prompt |
| `lib/population_simulator/simulation/cafe_runner.ex` | Orchestrates café round |
| `lib/population_simulator/simulation/cafe_response_validator.ex` | Validates café LLM response |
| `lib/population_simulator/simulation/introspection_prompt_builder.ex` | Builds introspection prompt |
| `lib/population_simulator/simulation/introspection_runner.ex` | Orchestrates introspection round |
| `lib/population_simulator/simulation/consciousness_loader.ex` | Loads narrative + cafés for PromptBuilder |
| `lib/mix/tasks/sim.cafe.ex` | Mix task to query café conversations |
| `lib/mix/tasks/sim.introspect.ex` | Mix task to run/query introspection |
| `test/population_simulator/simulation/cafe_grouper_test.exs` | Unit tests for grouping |
| `test/population_simulator/simulation/cafe_response_validator_test.exs` | Unit tests for café validation |

### Modified files

| File | Change |
|------|--------|
| `lib/population_simulator/simulation/prompt_builder.ex` | Add `build/5` with consciousness context |
| `lib/population_simulator/simulation/measure_runner.ex` | Load consciousness data, use build/5 |
| `lib/mix/tasks/sim.run.ex` | Add `--cafe` flag to trigger café round after measure |

---

## Task 1: Database Migrations

**Files:**
- Create: `priv/repo/migrations/20260403100000_create_cafe_sessions.exs`
- Create: `priv/repo/migrations/20260403100001_create_actor_summaries.exs`

- [ ] **Step 1: Create café migrations**

```elixir
# priv/repo/migrations/20260403100000_create_cafe_sessions.exs
defmodule PopulationSimulator.Repo.Migrations.CreateCafeSessions do
  use Ecto.Migration

  def change do
    create table(:cafe_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :group_key, :string, null: false
      add :participant_ids, :text, null: false
      add :participant_names, :text, null: false
      add :conversation, :text, null: false
      add :conversation_summary, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:cafe_sessions, [:measure_id])
    create index(:cafe_sessions, [:group_key])

    create table(:cafe_effects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cafe_session_id, references(:cafe_sessions, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :mood_deltas, :text, null: false
      add :belief_deltas, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:cafe_effects, [:cafe_session_id])
    create index(:cafe_effects, [:actor_id])
  end
end
```

- [ ] **Step 2: Create actor_summaries migration**

```elixir
# priv/repo/migrations/20260403100001_create_actor_summaries.exs
defmodule PopulationSimulator.Repo.Migrations.CreateActorSummaries do
  use Ecto.Migration

  def change do
    create table(:actor_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :narrative, :text, null: false
      add :self_observations, :text, null: false
      add :version, :integer, null: false, default: 1
      add :measure_id, references(:measures, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:actor_summaries, [:actor_id])
    create index(:actor_summaries, [:actor_id, :version], unique: true)
  end
end
```

- [ ] **Step 3: Run migrations**

Run: `mix ecto.migrate`
Expected: Both tables created successfully.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/20260403100000_create_cafe_sessions.exs priv/repo/migrations/20260403100001_create_actor_summaries.exs
git commit -m "Add migrations for cafe_sessions, cafe_effects, and actor_summaries"
```

---

## Task 2: Ecto Schemas

**Files:**
- Create: `lib/population_simulator/simulation/cafe_session.ex`
- Create: `lib/population_simulator/simulation/cafe_effect.ex`
- Create: `lib/population_simulator/simulation/actor_summary.ex`

- [ ] **Step 1: Create CafeSession schema**

```elixir
# lib/population_simulator/simulation/cafe_session.ex
defmodule PopulationSimulator.Simulation.CafeSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias PopulationSimulator.Simulation.{CafeEffect, Measure}
  alias PopulationSimulator.Actors.Actor

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cafe_sessions" do
    belongs_to :measure, Measure
    has_many :effects, CafeEffect
    field :group_key, :string
    field :participant_ids, :string
    field :participant_names, :string
    field :conversation, :string
    field :conversation_summary, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:measure_id, :group_key, :participant_ids, :participant_names, :conversation, :conversation_summary])
    |> validate_required([:measure_id, :group_key, :participant_ids, :participant_names, :conversation, :conversation_summary])
  end

  def new(measure_id, group_key, participant_ids, participant_names, conversation, summary) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      measure_id: measure_id,
      group_key: group_key,
      participant_ids: Jason.encode!(participant_ids),
      participant_names: Jason.encode!(participant_names),
      conversation: Jason.encode!(conversation),
      conversation_summary: summary,
      inserted_at: now,
      updated_at: now
    }
  end
end
```

- [ ] **Step 2: Create CafeEffect schema**

```elixir
# lib/population_simulator/simulation/cafe_effect.ex
defmodule PopulationSimulator.Simulation.CafeEffect do
  use Ecto.Schema
  import Ecto.Changeset

  alias PopulationSimulator.Simulation.CafeSession
  alias PopulationSimulator.Actors.Actor

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cafe_effects" do
    belongs_to :cafe_session, CafeSession
    belongs_to :actor, Actor
    field :mood_deltas, :string
    field :belief_deltas, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(effect, attrs) do
    effect
    |> cast(attrs, [:cafe_session_id, :actor_id, :mood_deltas, :belief_deltas])
    |> validate_required([:cafe_session_id, :actor_id, :mood_deltas, :belief_deltas])
  end

  def new(cafe_session_id, actor_id, mood_deltas, belief_deltas) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      cafe_session_id: cafe_session_id,
      actor_id: actor_id,
      mood_deltas: Jason.encode!(mood_deltas),
      belief_deltas: Jason.encode!(belief_deltas),
      inserted_at: now,
      updated_at: now
    }
  end
end
```

- [ ] **Step 3: Create ActorSummary schema**

```elixir
# lib/population_simulator/simulation/actor_summary.ex
defmodule PopulationSimulator.Simulation.ActorSummary do
  use Ecto.Schema
  import Ecto.Changeset

  alias PopulationSimulator.Actors.Actor
  alias PopulationSimulator.Simulation.Measure

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_summaries" do
    belongs_to :actor, Actor
    belongs_to :measure, Measure
    field :narrative, :string
    field :self_observations, :string
    field :version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [:actor_id, :measure_id, :narrative, :self_observations, :version])
    |> validate_required([:actor_id, :narrative, :self_observations, :version])
  end

  def new(actor_id, measure_id, narrative, self_observations, version) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      narrative: narrative,
      self_observations: Jason.encode!(self_observations),
      version: version,
      inserted_at: now,
      updated_at: now
    }
  end
end
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/cafe_session.ex lib/population_simulator/simulation/cafe_effect.ex lib/population_simulator/simulation/actor_summary.ex
git commit -m "Add Ecto schemas for CafeSession, CafeEffect, and ActorSummary"
```

---

## Task 3: CafeGrouper

**Files:**
- Create: `lib/population_simulator/simulation/cafe_grouper.ex`
- Create: `test/population_simulator/simulation/cafe_grouper_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# test/population_simulator/simulation/cafe_grouper_test.exs
defmodule PopulationSimulator.Simulation.CafeGrouperTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.CafeGrouper

  defp make_actor(id, zone, stratum) do
    %{id: id, zone: zone, profile: %{"stratum" => stratum}}
  end

  describe "group/1" do
    test "groups actors by zone and stratum band" do
      actors = [
        make_actor("a1", "suburbs_outer", "destitute"),
        make_actor("a2", "suburbs_outer", "low"),
        make_actor("a3", "suburbs_outer", "destitute"),
        make_actor("a4", "suburbs_inner", "upper_middle"),
        make_actor("a5", "suburbs_inner", "upper"),
      ]

      groups = CafeGrouper.group(actors)

      assert length(groups) == 2
      outer_group = Enum.find(groups, fn {key, _} -> key == "suburbs_outer:low" end)
      assert outer_group != nil
      {_, outer_actors} = outer_group
      assert length(outer_actors) == 3
    end

    test "splits groups larger than 7 into sub-tables" do
      actors = for i <- 1..12, do: make_actor("a#{i}", "caba_north", "upper_middle")

      groups = CafeGrouper.group(actors)

      assert length(groups) == 2
      sizes = Enum.map(groups, fn {_, actors} -> length(actors) end) |> Enum.sort()
      assert sizes == [5, 7] or sizes == [6, 6]
    end

    test "groups of fewer than 3 are merged with nearest affinity" do
      actors = [
        make_actor("a1", "suburbs_outer", "upper"),
        make_actor("a2", "suburbs_outer", "upper"),
        make_actor("a3", "suburbs_outer", "low"),
        make_actor("a4", "suburbs_outer", "low"),
        make_actor("a5", "suburbs_outer", "low"),
        make_actor("a6", "suburbs_outer", "low"),
        make_actor("a7", "suburbs_outer", "low"),
      ]

      groups = CafeGrouper.group(actors)

      # The 2 uppers should be merged into the low group or form a combined table
      all_actors = groups |> Enum.flat_map(fn {_, a} -> a end)
      assert length(all_actors) == 7
      assert Enum.all?(groups, fn {_, a} -> length(a) >= 3 end)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/population_simulator/simulation/cafe_grouper_test.exs`
Expected: FAIL — module CafeGrouper not found.

- [ ] **Step 3: Implement CafeGrouper**

```elixir
# lib/population_simulator/simulation/cafe_grouper.ex
defmodule PopulationSimulator.Simulation.CafeGrouper do
  @moduledoc """
  Groups actors into café tables by zone + stratum affinity.
  Tables are 5-7 actors. Groups < 3 are merged with nearest band.
  """

  @min_table_size 3
  @max_table_size 7

  @stratum_bands %{
    "destitute" => "low",
    "low" => "low",
    "lower_middle" => "middle",
    "middle" => "middle",
    "upper_middle" => "upper",
    "upper" => "upper"
  }

  def group(actors) do
    actors
    |> Enum.group_by(fn actor -> group_key(actor) end)
    |> merge_small_groups()
    |> Enum.flat_map(fn {key, actors} -> split_large_group(key, actors) end)
  end

  defp group_key(actor) do
    zone = to_string(actor.zone)
    stratum = actor.profile["stratum"] || "middle"
    band = Map.get(@stratum_bands, stratum, "middle")
    "#{zone}:#{band}"
  end

  defp merge_small_groups(groups) do
    {small, ok} = Enum.split_with(groups, fn {_, actors} -> length(actors) < @min_table_size end)

    Enum.reduce(small, ok, fn {key, actors}, acc ->
      zone = key |> String.split(":") |> List.first()
      best_match = Enum.find_index(acc, fn {k, _} -> String.starts_with?(k, zone <> ":") end)

      if best_match do
        {match_key, match_actors} = Enum.at(acc, best_match)
        List.replace_at(acc, best_match, {match_key, match_actors ++ actors})
      else
        # No same-zone group found; add as its own group if >= 1 actor
        if length(actors) >= 1, do: acc ++ [{key, actors}], else: acc
      end
    end)
  end

  defp split_large_group(key, actors) when length(actors) <= @max_table_size do
    [{key, actors}]
  end

  defp split_large_group(key, actors) do
    actors
    |> Enum.shuffle()
    |> Enum.chunk_every(@max_table_size)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      sub_key = if idx == 0, do: key, else: "#{key}:#{idx}"
      {sub_key, chunk}
    end)
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/population_simulator/simulation/cafe_grouper_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/cafe_grouper.ex test/population_simulator/simulation/cafe_grouper_test.exs
git commit -m "Add CafeGrouper for zone+stratum affinity table assignment"
```

---

## Task 4: CafePromptBuilder

**Files:**
- Create: `lib/population_simulator/simulation/cafe_prompt_builder.ex`

- [ ] **Step 1: Implement CafePromptBuilder**

```elixir
# lib/population_simulator/simulation/cafe_prompt_builder.ex
defmodule PopulationSimulator.Simulation.CafePromptBuilder do
  @moduledoc """
  Builds the group conversation prompt for a café table.
  """

  @argentine_names ~w(María Jorge Carlos Ana Laura Pedro Silvia Roberto Graciela Daniel Marta Luis)

  def build(measure, participants) do
    names = assign_names(participants)
    participant_block = Enum.map_join(participants, "\n\n", fn p -> participant_section(p, names) end)

    """
    Sos un narrador que simula una conversación entre vecinos argentinos del Gran Buenos Aires que se juntan a tomar un café después de enterarse de la siguiente medida económica:

    === MEDIDA ===
    Título: #{measure.title}
    Descripción: #{measure.description}

    === PARTICIPANTES ===
    #{participant_block}

    === INSTRUCCIONES ===
    Generá una conversación realista entre estos vecinos discutiendo la medida. Cada uno habla desde su situación personal y puede influir en los demás. La conversación debe reflejar los perfiles, las decisiones que tomaron, y su estado de ánimo actual.

    Respondé EXCLUSIVAMENTE con un JSON válido (sin markdown, sin texto extra) con esta estructura:
    {
      "conversation": [
        {"actor_id": "<uuid>", "name": "<nombre>", "message": "<lo que dice>"},
        ...
      ],
      "conversation_summary": "<resumen de 2-3 oraciones de qué se habló>",
      "effects": [
        {
          "actor_id": "<uuid>",
          "mood_deltas": {
            "economic_confidence": <float entre -1.0 y 1.0>,
            "government_trust": <float entre -1.0 y 1.0>,
            "personal_wellbeing": <float entre -1.0 y 1.0>,
            "social_anger": <float entre -1.0 y 1.0>,
            "future_outlook": <float entre -1.0 y 1.0>
          },
          "belief_deltas": {
            "modified_edges": [{"from": "<node>", "to": "<node>", "weight_delta": <float entre -0.4 y 0.4>}],
            "new_nodes": []
          }
        }
      ]
    }

    REGLAS:
    - La conversación debe tener entre 8 y 15 mensajes. Todos los participantes deben hablar al menos una vez.
    - mood_deltas: cada valor entre -1.0 y 1.0. Omití dimensiones sin cambio.
    - belief_deltas: máximo 2 modified_edges por actor. new_nodes siempre vacío.
    - effects debe tener exactamente una entrada por cada participante.
    - Todo en español rioplatense.
    """
    |> String.trim()
    |> then(fn prompt -> {prompt, names} end)
  end

  defp assign_names(participants) do
    names = Enum.shuffle(@argentine_names)

    participants
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> {p.actor_id, Enum.at(names, i, "Vecino#{i + 1}")} end)
    |> Map.new()
  end

  defp participant_section(participant, names) do
    name = Map.get(names, participant.actor_id, "Vecino")
    profile = participant.profile
    decision = participant.decision
    mood = participant.mood

    agreement_text = if decision.agreement, do: "APRUEBA", else: "RECHAZA"

    """
    --- #{name} (ID: #{participant.actor_id}) ---
    Edad: #{profile["age"]} | Sexo: #{profile["sex"]} | Estrato: #{profile["stratum"]}
    Zona: #{profile["zone"]} | Empleo: #{profile["employment_type"]}
    Educación: #{profile["education_level"]}
    Decisión sobre la medida: #{agreement_text} (intensidad #{decision.intensity}/10)
    Razón: #{decision.reasoning}
    Humor actual: confianza_económica=#{mood.economic_confidence}, confianza_gobierno=#{mood.government_trust}, bienestar=#{mood.personal_wellbeing}, enojo_social=#{mood.social_anger}, perspectiva_futuro=#{mood.future_outlook}
    """
    |> String.trim()
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/cafe_prompt_builder.ex
git commit -m "Add CafePromptBuilder for group conversation prompts"
```

---

## Task 5: CafeResponseValidator

**Files:**
- Create: `lib/population_simulator/simulation/cafe_response_validator.ex`
- Create: `test/population_simulator/simulation/cafe_response_validator_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# test/population_simulator/simulation/cafe_response_validator_test.exs
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/population_simulator/simulation/cafe_response_validator_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement CafeResponseValidator**

```elixir
# lib/population_simulator/simulation/cafe_response_validator.ex
defmodule PopulationSimulator.Simulation.CafeResponseValidator do
  @moduledoc """
  Validates and clamps LLM responses for café group conversations.
  Mood deltas capped at +-1.0, max 2 belief edges per actor, no emergent nodes.
  """

  @max_mood_delta 1.0
  @max_belief_edges 2
  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)

  def validate(response, expected_actor_ids) do
    with :ok <- validate_structure(response),
         :ok <- validate_actors(response["effects"], expected_actor_ids) do
      validated =
        response
        |> Map.update!("effects", fn effects -> Enum.map(effects, &validate_effect/1) end)

      {:ok, validated}
    end
  end

  defp validate_structure(response) do
    cond do
      not is_list(response["conversation"]) -> {:error, "missing conversation array"}
      not is_binary(response["conversation_summary"]) -> {:error, "missing conversation_summary"}
      not is_list(response["effects"]) -> {:error, "missing effects array"}
      true -> :ok
    end
  end

  defp validate_actors(effects, expected_ids) do
    effect_ids = Enum.map(effects, & &1["actor_id"]) |> MapSet.new()
    expected = MapSet.new(expected_ids)

    if MapSet.subset?(expected, effect_ids) do
      :ok
    else
      {:error, "effects missing for actors: #{inspect(MapSet.difference(expected, effect_ids))}"}
    end
  end

  defp validate_effect(effect) do
    effect
    |> Map.update!("mood_deltas", &clamp_mood_deltas/1)
    |> Map.update!("belief_deltas", &clamp_belief_deltas/1)
  end

  defp clamp_mood_deltas(deltas) when is_map(deltas) do
    Map.new(deltas, fn {key, val} ->
      if key in @mood_dimensions do
        {key, clamp(val, -@max_mood_delta, @max_mood_delta)}
      else
        {key, val}
      end
    end)
  end

  defp clamp_mood_deltas(_), do: %{}

  defp clamp_belief_deltas(deltas) when is_map(deltas) do
    %{
      "modified_edges" => deltas |> Map.get("modified_edges", []) |> Enum.take(@max_belief_edges),
      "new_nodes" => []
    }
  end

  defp clamp_belief_deltas(_), do: %{"modified_edges" => [], "new_nodes" => []}

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, _, _), do: 0.0
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/population_simulator/simulation/cafe_response_validator_test.exs`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/cafe_response_validator.ex test/population_simulator/simulation/cafe_response_validator_test.exs
git commit -m "Add CafeResponseValidator with mood/belief clamping"
```

---

## Task 6: CafeRunner

**Files:**
- Create: `lib/population_simulator/simulation/cafe_runner.ex`

- [ ] **Step 1: Implement CafeRunner**

```elixir
# lib/population_simulator/simulation/cafe_runner.ex
defmodule PopulationSimulator.Simulation.CafeRunner do
  @moduledoc """
  Orchestrates café round after a measure: groups actors, dispatches LLM calls,
  persists dialogues and applies mood/belief effects.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{
    CafeGrouper,
    CafePromptBuilder,
    CafeResponseValidator,
    CafeSession,
    CafeEffect,
    ActorMood,
    ActorBelief,
    BeliefGraph
  }
  alias PopulationSimulator.LLM.ClaudeClient

  require Logger

  def run(measure, actors, decisions, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 15)

    # Build participant data: actor + their decision + current mood
    participants = build_participants(actors, decisions)

    # Group into café tables
    tables = CafeGrouper.group(participants)
    total = length(tables)

    Logger.info("Café round: #{total} tables for measure #{measure.id}")

    # Process tables concurrently
    results =
      tables
      |> Task.async_stream(
        fn {group_key, table_actors} ->
          process_table(measure, group_key, table_actors)
        end,
        max_concurrency: concurrency,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0}, fn
        {:ok, {:ok, _}}, acc -> %{acc | ok: acc.ok + 1}
        _, acc -> %{acc | error: acc.error + 1}
      end)

    Logger.info("Café complete: #{results.ok}/#{total} tables OK, #{results.error} errors")
    results
  end

  defp build_participants(actors, decisions) do
    decision_map = Map.new(decisions, fn d -> {d.actor_id, d} end)

    Enum.flat_map(actors, fn actor ->
      case Map.get(decision_map, actor.id) do
        nil -> []
        decision ->
          mood = load_latest_mood(actor.id)
          [%{
            actor_id: actor.id,
            zone: actor.zone,
            profile: actor.profile,
            decision: decision,
            mood: mood
          }]
      end
    end)
  end

  defp load_latest_mood(actor_id) do
    import Ecto.Query
    Repo.one(
      from(m in ActorMood,
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    ) || %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
  end

  defp process_table(measure, group_key, table_actors) do
    {prompt, names} = CafePromptBuilder.build(measure, table_actors)
    actor_ids = Enum.map(table_actors, & &1.actor_id)

    case ClaudeClient.complete(prompt, max_tokens: 2048, temperature: 0.3) do
      {:ok, response} ->
        case CafeResponseValidator.validate(response, actor_ids) do
          {:ok, validated} ->
            persist_cafe(measure.id, group_key, actor_ids, names, validated, table_actors)
            {:ok, group_key}

          {:error, reason} ->
            Logger.warning("Café validation failed for #{group_key}: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Café LLM call failed for #{group_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp persist_cafe(measure_id, group_key, actor_ids, names, validated, table_actors) do
    session_row = CafeSession.new(
      measure_id,
      group_key,
      actor_ids,
      names,
      validated["conversation"],
      validated["conversation_summary"]
    )

    Repo.insert_all(CafeSession, [session_row])

    # Persist effects and apply mood/belief updates
    Enum.each(validated["effects"], fn effect ->
      effect_row = CafeEffect.new(
        session_row.id,
        effect["actor_id"],
        effect["mood_deltas"],
        effect["belief_deltas"]
      )
      Repo.insert_all(CafeEffect, [effect_row])

      apply_mood_deltas(effect["actor_id"], measure_id, effect["mood_deltas"])
      apply_belief_deltas(effect["actor_id"], measure_id, effect["belief_deltas"], table_actors)
    end)
  end

  defp apply_mood_deltas(actor_id, measure_id, deltas) when map_size(deltas) > 0 do
    import Ecto.Query

    current = Repo.one(
      from(m in ActorMood,
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    )

    if current do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      new_mood = %{
        id: Ecto.UUID.generate(),
        actor_id: actor_id,
        measure_id: measure_id,
        decision_id: nil,
        economic_confidence: clamp_mood(current.economic_confidence + Map.get(deltas, "economic_confidence", 0)),
        government_trust: clamp_mood(current.government_trust + Map.get(deltas, "government_trust", 0)),
        personal_wellbeing: clamp_mood(current.personal_wellbeing + Map.get(deltas, "personal_wellbeing", 0)),
        social_anger: clamp_mood(current.social_anger + Map.get(deltas, "social_anger", 0)),
        future_outlook: clamp_mood(current.future_outlook + Map.get(deltas, "future_outlook", 0)),
        narrative: current.narrative,
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(ActorMood, [new_mood])
    end
  end

  defp apply_mood_deltas(_, _, _), do: :ok

  defp apply_belief_deltas(actor_id, measure_id, %{"modified_edges" => edges}, _table_actors)
       when length(edges) > 0 do
    import Ecto.Query

    current = Repo.one(
      from(b in ActorBelief,
        where: b.actor_id == ^actor_id,
        order_by: [desc: b.inserted_at],
        limit: 1
      )
    )

    if current do
      delta = %{"modified_edges" => edges, "new_edges" => [], "new_nodes" => [], "removed_edges" => []}
      new_graph = BeliefGraph.apply_delta(current.graph, delta)
      dampened = BeliefGraph.apply_edge_damping(new_graph, current.graph, 0.4)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      new_belief = %{
        id: Ecto.UUID.generate(),
        actor_id: actor_id,
        measure_id: measure_id,
        decision_id: nil,
        graph: dampened,
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(ActorBelief, [new_belief])
    end
  end

  defp apply_belief_deltas(_, _, _, _), do: :ok

  defp clamp_mood(val), do: val |> round() |> max(1) |> min(10)
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/cafe_runner.ex
git commit -m "Add CafeRunner to orchestrate group conversations"
```

---

## Task 7: IntrospectionPromptBuilder + IntrospectionRunner

**Files:**
- Create: `lib/population_simulator/simulation/introspection_prompt_builder.ex`
- Create: `lib/population_simulator/simulation/introspection_runner.ex`

- [ ] **Step 1: Implement IntrospectionPromptBuilder**

```elixir
# lib/population_simulator/simulation/introspection_prompt_builder.ex
defmodule PopulationSimulator.Simulation.IntrospectionPromptBuilder do
  @moduledoc """
  Builds the introspection prompt for autobiographical narrative generation.
  """

  def build(profile, previous_narrative, decisions, cafe_summaries, current_mood) do
    narrative_section =
      if previous_narrative && previous_narrative != "" do
        """
        === TU RELATO PERSONAL ANTERIOR ===
        #{previous_narrative}
        """
      else
        "=== PRIMERA INTROSPECCIÓN ===\nEsta es tu primera reflexión. Construí tu relato desde cero."
      end

    decisions_section =
      decisions
      |> Enum.map_join("\n", fn d ->
        status = if d.agreement, do: "Aprobaste", else: "Rechazaste"
        "- #{d.measure_title}: #{status} (intensidad #{d.intensity}/10). #{d.reasoning}"
      end)

    cafes_section =
      cafe_summaries
      |> Enum.map_join("\n", fn s -> "- #{s}" end)

    mood_section = """
    Confianza económica: #{current_mood.economic_confidence}/10
    Confianza en el gobierno: #{current_mood.government_trust}/10
    Bienestar personal: #{current_mood.personal_wellbeing}/10
    Enojo social: #{current_mood.social_anger}/10
    Perspectiva de futuro: #{current_mood.future_outlook}/10
    """

    """
    Sos un ciudadano argentino del Gran Buenos Aires. A continuación tenés tu perfil, tu historia reciente, y tus conversaciones con vecinos. Tu tarea es reflexionar sobre todo esto y reescribir tu relato personal.

    === TU PERFIL ===
    Edad: #{profile["age"]} | Sexo: #{profile["sex"]} | Estrato: #{profile["stratum"]}
    Zona: #{profile["zone"]} | Empleo: #{profile["employment_type"]}
    Educación: #{profile["education_level"]}
    Ingreso: $#{profile["income"]}

    #{narrative_section}

    === ÚLTIMAS DECISIONES ===
    #{decisions_section}

    === CONVERSACIONES CON VECINOS ===
    #{cafes_section}

    === TU HUMOR ACTUAL ===
    #{mood_section}

    === INSTRUCCIONES ===
    Reflexioná sobre lo que te pasó, qué patrones notás en tus reacciones, y reescribí tu relato personal (máximo 200 palabras). También identificá hasta 5 observaciones sobre vos mismo.

    Respondé EXCLUSIVAMENTE con JSON válido:
    {
      "narrative": "<tu relato personal actualizado, máximo 200 palabras, en primera persona>",
      "self_observations": ["<observación 1>", "<observación 2>", ...]
    }
    """
    |> String.trim()
  end
end
```

- [ ] **Step 2: Implement IntrospectionRunner**

```elixir
# lib/population_simulator/simulation/introspection_runner.ex
defmodule PopulationSimulator.Simulation.IntrospectionRunner do
  @moduledoc """
  Orchestrates introspection round: each actor reflects on recent experiences
  and generates/updates their autobiographical narrative.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{
    IntrospectionPromptBuilder,
    ActorSummary,
    ActorMood
  }
  alias PopulationSimulator.LLM.ClaudeClient

  import Ecto.Query
  require Logger

  def run(measure, actors, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 30)
    total = length(actors)

    Logger.info("Introspection round: #{total} actors for measure #{measure.id}")

    results =
      actors
      |> Task.async_stream(
        fn actor -> introspect_actor(actor, measure) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0}, fn
        {:ok, {:ok, _}}, acc -> %{acc | ok: acc.ok + 1}
        _, acc -> %{acc | error: acc.error + 1}
      end)

    Logger.info("Introspection complete: #{results.ok}/#{total} OK, #{results.error} errors")
    results
  end

  defp introspect_actor(actor, measure) do
    previous = load_latest_summary(actor.id)
    previous_narrative = if previous, do: previous.narrative, else: nil
    version = if previous, do: previous.version + 1, else: 1

    decisions = load_recent_decisions(actor.id, 3)
    cafe_summaries = load_recent_cafe_summaries(actor.id, 3)
    current_mood = load_latest_mood(actor.id)

    prompt = IntrospectionPromptBuilder.build(
      actor.profile,
      previous_narrative,
      decisions,
      cafe_summaries,
      current_mood
    )

    case ClaudeClient.complete(prompt, max_tokens: 1024, temperature: 0.3) do
      {:ok, response} ->
        narrative = response["narrative"] || ""
        observations = response["self_observations"] || []

        # Clamp: max 200 words narrative, max 5 observations
        trimmed_narrative = narrative |> String.split() |> Enum.take(200) |> Enum.join(" ")
        trimmed_observations = Enum.take(observations, 5)

        row = ActorSummary.new(actor.id, measure.id, trimmed_narrative, trimmed_observations, version)
        Repo.insert_all(ActorSummary, [row])
        {:ok, actor.id}

      {:error, reason} ->
        Logger.warning("Introspection failed for actor #{actor.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_latest_summary(actor_id) do
    Repo.one(
      from(s in ActorSummary,
        where: s.actor_id == ^actor_id,
        order_by: [desc: s.version],
        limit: 1
      )
    )
  end

  defp load_recent_decisions(actor_id, limit) do
    Repo.all(
      from(d in PopulationSimulator.Simulation.Decision,
        join: m in PopulationSimulator.Simulation.Measure, on: d.measure_id == m.id,
        where: d.actor_id == ^actor_id,
        order_by: [desc: d.inserted_at],
        limit: ^limit,
        select: %{
          agreement: d.agreement,
          intensity: d.intensity,
          reasoning: d.reasoning,
          measure_title: m.title
        }
      )
    )
    |> Enum.reverse()
  end

  defp load_recent_cafe_summaries(actor_id, limit) do
    Repo.all(
      from(cs in PopulationSimulator.Simulation.CafeSession,
        join: ce in PopulationSimulator.Simulation.CafeEffect,
          on: ce.cafe_session_id == cs.id,
        where: ce.actor_id == ^actor_id,
        order_by: [desc: cs.inserted_at],
        limit: ^limit,
        select: cs.conversation_summary
      )
    )
    |> Enum.reverse()
  end

  defp load_latest_mood(actor_id) do
    Repo.one(
      from(m in ActorMood,
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    ) || %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
  end
end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator/simulation/introspection_prompt_builder.ex lib/population_simulator/simulation/introspection_runner.ex
git commit -m "Add IntrospectionRunner and IntrospectionPromptBuilder"
```

---

## Task 8: ConsciousnessLoader + PromptBuilder build/5

**Files:**
- Create: `lib/population_simulator/simulation/consciousness_loader.ex`
- Modify: `lib/population_simulator/simulation/prompt_builder.ex`

- [ ] **Step 1: Implement ConsciousnessLoader**

```elixir
# lib/population_simulator/simulation/consciousness_loader.ex
defmodule PopulationSimulator.Simulation.ConsciousnessLoader do
  @moduledoc """
  Loads consciousness context (narrative + observations + café summaries)
  for an actor to inject into PromptBuilder.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{ActorSummary, CafeSession, CafeEffect}
  import Ecto.Query

  def load(actor_id) do
    summary = load_latest_summary(actor_id)
    cafe_summaries = load_recent_cafe_summaries(actor_id, 2)

    case summary do
      nil -> nil
      _ ->
        %{
          narrative: summary.narrative,
          self_observations: Jason.decode!(summary.self_observations),
          cafe_summaries: cafe_summaries
        }
    end
  end

  defp load_latest_summary(actor_id) do
    Repo.one(
      from(s in ActorSummary,
        where: s.actor_id == ^actor_id,
        order_by: [desc: s.version],
        limit: 1
      )
    )
  end

  defp load_recent_cafe_summaries(actor_id, limit) do
    Repo.all(
      from(cs in CafeSession,
        join: ce in CafeEffect, on: ce.cafe_session_id == cs.id,
        where: ce.actor_id == ^actor_id,
        order_by: [desc: cs.inserted_at],
        limit: ^limit,
        select: cs.conversation_summary
      )
    )
    |> Enum.reverse()
  end
end
```

- [ ] **Step 2: Add build/5 to PromptBuilder**

Add to the end of `lib/population_simulator/simulation/prompt_builder.ex`, before the last `end`:

```elixir
  def build(profile, measure, mood_context, belief_graph, consciousness) when is_map(profile) do
    base = build(profile, measure, mood_context, belief_graph)

    consciousness_block = build_consciousness_block(consciousness)

    # Insert consciousness block after profile section, before measure
    String.replace(base, "=== MEDIDA ===", "#{consciousness_block}\n=== MEDIDA ===")
  end

  defp build_consciousness_block(nil), do: ""

  defp build_consciousness_block(consciousness) do
    narrative = consciousness[:narrative] || ""
    observations = consciousness[:self_observations] || []
    cafes = consciousness[:cafe_summaries] || []

    observations_text =
      if observations != [] do
        obs = Enum.map_join(observations, "\n", fn o -> "- #{o}" end)
        "\n\nLo que observás de vos mismo:\n#{obs}"
      else
        ""
      end

    cafes_text =
      if cafes != [] do
        c = Enum.map_join(cafes, "\n", fn s -> "- #{s}" end)
        "\n\n=== CONVERSACIONES RECIENTES CON VECINOS ===\n#{c}"
      else
        ""
      end

    """
    === QUIÉN SOS ===
    #{narrative}#{observations_text}#{cafes_text}

    """
  end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator/simulation/consciousness_loader.ex lib/population_simulator/simulation/prompt_builder.ex
git commit -m "Add ConsciousnessLoader and PromptBuilder build/5 with consciousness context"
```

---

## Task 9: Integrate into MeasureRunner

**Files:**
- Modify: `lib/population_simulator/simulation/measure_runner.ex`

- [ ] **Step 1: Update evaluate_actor to load consciousness and use build/5**

In `measure_runner.ex`, find the section in `evaluate_actor` where the prompt is built (the `cond` block that selects arity 2/3/4). Replace it with:

```elixir
      # After loading mood_state, belief_state, history — add consciousness loading
      consciousness = PopulationSimulator.Simulation.ConsciousnessLoader.load(actor.id)

      prompt =
        cond do
          mood_state && belief_state && consciousness ->
            PromptBuilder.build(profile, measure, mood_context, filtered_belief, consciousness)
          mood_state && belief_state ->
            PromptBuilder.build(profile, measure, mood_context, filtered_belief)
          mood_state ->
            PromptBuilder.build(profile, measure, mood_context)
          true ->
            PromptBuilder.build(profile, measure)
        end
```

- [ ] **Step 2: Verify compilation and tests pass**

Run: `mix compile && mix test`
Expected: All existing tests pass. Consciousness is nil for actors without it, so arity 4 is used (backwards compatible).

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/measure_runner.ex
git commit -m "Integrate consciousness loading into MeasureRunner evaluate_actor"
```

---

## Task 10: Mix Tasks — sim.run --cafe + sim.cafe + sim.introspect

**Files:**
- Modify: `lib/mix/tasks/sim.run.ex`
- Create: `lib/mix/tasks/sim.cafe.ex`
- Create: `lib/mix/tasks/sim.introspect.ex`

- [ ] **Step 1: Add --cafe flag to sim.run**

In `lib/mix/tasks/sim.run.ex`, after the MeasureRunner.run call that produces results, add:

```elixir
      # After MeasureRunner.run completes:
      if Keyword.get(parsed, :cafe, false) do
        IO.puts("\nStarting café round...")
        actors = load_population_actors(population_id)
        decisions = load_measure_decisions(measure_id)
        cafe_results = PopulationSimulator.Simulation.CafeRunner.run(measure, actors, decisions, concurrency: concurrency)
        IO.puts("Café: #{cafe_results.ok} tables OK, #{cafe_results.error} errors")

        # Check if introspection should trigger (every 3 measures)
        measure_count = count_measures_for_population(population_id)
        if rem(measure_count, 3) == 0 do
          IO.puts("\nTriggering introspection (measure ##{measure_count})...")
          intro_results = PopulationSimulator.Simulation.IntrospectionRunner.run(measure, actors, concurrency: concurrency)
          IO.puts("Introspection: #{intro_results.ok} actors OK, #{intro_results.error} errors")
        end
      end
```

Add `:cafe` to the OptionParser switches as a boolean.

- [ ] **Step 2: Create sim.cafe mix task**

```elixir
# lib/mix/tasks/sim.cafe.ex
defmodule Mix.Tasks.Sim.Cafe do
  use Mix.Task

  alias PopulationSimulator.Repo
  import Ecto.Query

  @shortdoc "Query café conversations"

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [measure_id: :string, zone: :string, actor_id: :string, limit: :integer]
      )

    limit = Keyword.get(parsed, :limit, 10)

    cond do
      actor_id = parsed[:actor_id] ->
        show_actor_cafes(actor_id, limit)

      measure_id = parsed[:measure_id] ->
        zone = parsed[:zone]
        show_measure_cafes(measure_id, zone, limit)

      true ->
        IO.puts("Usage:")
        IO.puts("  mix sim.cafe --measure-id <id> [--zone <zone>]")
        IO.puts("  mix sim.cafe --actor-id <id>")
    end
  end

  defp show_measure_cafes(measure_id, zone, limit) do
    query =
      from(cs in PopulationSimulator.Simulation.CafeSession,
        where: cs.measure_id == ^measure_id,
        order_by: [asc: cs.group_key],
        limit: ^limit
      )

    query = if zone, do: where(query, [cs], like(cs.group_key, ^"#{zone}%")), else: query

    cafes = Repo.all(query)

    Enum.each(cafes, fn cafe ->
      IO.puts("\n=== Mesa: #{cafe.group_key} ===")
      IO.puts("Resumen: #{cafe.conversation_summary}")
      IO.puts("")

      conversation = Jason.decode!(cafe.conversation)
      Enum.each(conversation, fn msg ->
        IO.puts("  #{msg["name"]}: #{msg["message"]}")
      end)
    end)

    IO.puts("\nTotal: #{length(cafes)} mesas")
  end

  defp show_actor_cafes(actor_id, limit) do
    cafes =
      Repo.all(
        from(cs in PopulationSimulator.Simulation.CafeSession,
          join: ce in PopulationSimulator.Simulation.CafeEffect,
            on: ce.cafe_session_id == cs.id,
          where: ce.actor_id == ^actor_id,
          order_by: [desc: cs.inserted_at],
          limit: ^limit,
          select: {cs, ce}
        )
      )

    Enum.each(cafes, fn {cafe, effect} ->
      IO.puts("\n=== Mesa: #{cafe.group_key} ===")
      IO.puts("Resumen: #{cafe.conversation_summary}")

      conversation = Jason.decode!(cafe.conversation)
      names = Jason.decode!(cafe.participant_names)
      actor_name = Map.get(names, actor_id, "???")

      Enum.each(conversation, fn msg ->
        prefix = if msg["actor_id"] == actor_id, do: ">>", else: "  "
        IO.puts("#{prefix} #{msg["name"]}: #{msg["message"]}")
      end)

      mood_deltas = Jason.decode!(effect.mood_deltas)
      IO.puts("\n  Efecto en humor: #{inspect(mood_deltas)}")
    end)
  end
end
```

- [ ] **Step 3: Create sim.introspect mix task**

```elixir
# lib/mix/tasks/sim.introspect.ex
defmodule Mix.Tasks.Sim.Introspect do
  use Mix.Task

  alias PopulationSimulator.Repo
  import Ecto.Query

  @shortdoc "Run or query actor introspection"

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [actor_id: :string, population: :string, run: :boolean]
      )

    cond do
      parsed[:run] && parsed[:population] ->
        run_introspection(parsed[:population])

      actor_id = parsed[:actor_id] ->
        show_actor_introspection(actor_id)

      population = parsed[:population] ->
        show_population_summary(population)

      true ->
        IO.puts("Usage:")
        IO.puts("  mix sim.introspect --actor-id <id>")
        IO.puts("  mix sim.introspect --population \"Name\"")
        IO.puts("  mix sim.introspect --run --population \"Name\"")
    end
  end

  defp show_actor_introspection(actor_id) do
    summaries =
      Repo.all(
        from(s in PopulationSimulator.Simulation.ActorSummary,
          where: s.actor_id == ^actor_id,
          order_by: [asc: s.version]
        )
      )

    if summaries == [] do
      IO.puts("No introspection data for actor #{actor_id}")
    else
      Enum.each(summaries, fn s ->
        observations = Jason.decode!(s.self_observations)
        IO.puts("\n=== Versión #{s.version} (#{s.inserted_at}) ===")
        IO.puts(s.narrative)
        IO.puts("\nObservaciones:")
        Enum.each(observations, fn o -> IO.puts("  - #{o}") end)
      end)
    end
  end

  defp show_population_summary(population_name) do
    actor_ids =
      Repo.all(
        from(ap in PopulationSimulator.Actors.ActorPopulation,
          join: p in PopulationSimulator.Actors.Population, on: ap.population_id == p.id,
          where: p.name == ^population_name,
          select: ap.actor_id
        )
      )

    count =
      Repo.one(
        from(s in PopulationSimulator.Simulation.ActorSummary,
          where: s.actor_id in ^actor_ids,
          select: count(fragment("DISTINCT ?", s.actor_id))
        )
      )

    IO.puts("Actors with introspection: #{count}/#{length(actor_ids)}")

    if count > 0 do
      max_version =
        Repo.one(
          from(s in PopulationSimulator.Simulation.ActorSummary,
            where: s.actor_id in ^actor_ids,
            select: max(s.version)
          )
        )
      IO.puts("Max introspection version: #{max_version}")
    end
  end

  defp run_introspection(population_name) do
    actors =
      Repo.all(
        from(a in PopulationSimulator.Actors.Actor,
          join: ap in PopulationSimulator.Actors.ActorPopulation, on: ap.actor_id == a.id,
          join: p in PopulationSimulator.Actors.Population, on: ap.population_id == p.id,
          where: p.name == ^population_name
        )
      )

    latest_measure =
      Repo.one(
        from(m in PopulationSimulator.Simulation.Measure,
          order_by: [desc: m.inserted_at],
          limit: 1
        )
      )

    if latest_measure do
      results = PopulationSimulator.Simulation.IntrospectionRunner.run(latest_measure, actors)
      IO.puts("Introspection: #{results.ok} OK, #{results.error} errors")
    else
      IO.puts("No measures found. Run a simulation first.")
    end
  end
end
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 5: Commit**

```bash
git add lib/mix/tasks/sim.run.ex lib/mix/tasks/sim.cafe.ex lib/mix/tasks/sim.introspect.ex
git commit -m "Add --cafe flag to sim.run, add sim.cafe and sim.introspect mix tasks"
```

---

## Task 11: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add consciousness documentation**

Add to the Architecture section after "Prompt arities":

```markdown
- **Consciousness**: 3 layers — autobiographical narrative (actor_summaries, updated every 3 measures via IntrospectionRunner), social interaction (cafe_sessions with full dialogue, CafeRunner groups by zone+stratum), metacognition (self_observations in actor_summaries). PromptBuilder.build/5 injects narrative + observations + café summaries.
```

Add to Commands section:

```bash
# Café conversations
mix sim.run --title "..." --description "..." --population "..." --cafe
mix sim.cafe --measure-id <id>
mix sim.cafe --measure-id <id> --zone suburbs_outer
mix sim.cafe --actor-id <id>

# Introspection
mix sim.introspect --actor-id <id>
mix sim.introspect --population "1000 personas"
mix sim.introspect --run --population "1000 personas"
```

Add to Core Modules table:

```markdown
| `CafeRunner` | Orchestrates café round: groups actors, LLM calls, persists dialogues + effects |
| `CafeGrouper` | Groups actors by zone+stratum into tables of 5-7 |
| `IntrospectionRunner` | Periodic reflection, generates autobiographical narratives |
| `ConsciousnessLoader` | Loads narrative + observations + café summaries for PromptBuilder |
```

Add to Database Schema tables:

```markdown
- **cafe_sessions** — group conversation per table per measure (full dialogue + summary)
- **cafe_effects** — per-actor mood/belief deltas from café conversations
- **actor_summaries** — autobiographical narrative versions (narrative + self_observations)
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md with consciousness architecture docs"
```

---

## Task 12: End-to-End Smoke Test

- [ ] **Step 1: Run a measure with --cafe**

```bash
export CLAUDE_API_KEY=<key>
mix sim.run --title "Test café" --description "El gobierno anuncia una suba del 5% en tarifas de luz y gas." --population "1000 personas" --cafe --concurrency 30
```

Expected: Measure completes, café round processes ~150 tables, no introspection yet (measure #1).

- [ ] **Step 2: Verify café data persisted**

```bash
mix sim.cafe --measure-id <id from step 1> --limit 3
```

Expected: Shows 3 café conversations with full dialogue.

- [ ] **Step 3: Run 2 more measures with --cafe to trigger introspection**

Run measures 2 and 3. On measure 3, introspection should auto-trigger.

- [ ] **Step 4: Verify introspection**

```bash
mix sim.introspect --population "1000 personas"
```

Expected: Shows actors with introspection data, version 1.

- [ ] **Step 5: Spot-check an actor's full journey**

```bash
# Pick an actor ID from the output
mix sim.introspect --actor-id <id>
mix sim.cafe --actor-id <id>
```

Expected: Narrative reflects their decisions and café conversations.

- [ ] **Step 6: Commit any fixes**

```bash
git add -A
git commit -m "Fix issues found during e2e smoke test"
```
