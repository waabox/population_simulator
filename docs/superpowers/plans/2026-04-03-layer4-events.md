# Layer 4: Personal Events — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After each measure, ~20% of actors receive LLM-generated personal events (measure-derived or life events) that modify their mood and profile, decaying over time.

**Architecture:** EventGenerator selects vulnerable actors via a weighted vulnerability score, then dispatches one LLM call per selected actor to generate a personalized event. Events persist in `actor_events` with mood_impact, profile_effects, and a duration counter. EventDecayer reduces remaining duration each measure and deactivates expired events. Active events are injected into prompts via PromptBuilder.

**Tech Stack:** Elixir/Ecto, SQLite3, Claude API (via ClaudeClient.complete_raw).

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `priv/repo/migrations/20260403300000_create_actor_events.exs` | actor_events table |
| `lib/population_simulator/simulation/actor_event.ex` | Ecto schema |
| `lib/population_simulator/simulation/event_generator.ex` | Select actors + generate events via LLM |
| `lib/population_simulator/simulation/event_prompt_builder.ex` | Build per-actor event prompt |
| `lib/population_simulator/simulation/event_response_validator.ex` | Validate event LLM response |
| `lib/population_simulator/simulation/event_decayer.ex` | Decay and deactivate events |
| `test/population_simulator/simulation/event_response_validator_test.exs` | Validator tests |
| `test/population_simulator/simulation/event_decayer_test.exs` | Decayer tests |

### Modified files

| File | Change |
|------|--------|
| `lib/population_simulator/simulation/consciousness_loader.ex` | Load active events for prompt |
| `lib/population_simulator/simulation/prompt_builder.ex` | Add events block to build/5 |
| `lib/mix/tasks/sim.run.ex` | Call EventGenerator + EventDecayer after MeasureRunner |

---

## Task 1: Migration + Schema

**Files:**
- Create: `priv/repo/migrations/20260403300000_create_actor_events.exs`
- Create: `lib/population_simulator/simulation/actor_event.ex`

- [ ] **Step 1: Create migration**

```elixir
# priv/repo/migrations/20260403300000_create_actor_events.exs
defmodule PopulationSimulator.Repo.Migrations.CreateActorEvents do
  use Ecto.Migration

  def change do
    create table(:actor_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :description, :text, null: false
      add :mood_impact, :text, null: false
      add :profile_effects, :text, null: false
      add :duration, :integer, null: false
      add :remaining, :integer, null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create index(:actor_events, [:actor_id])
    create index(:actor_events, [:actor_id, :active])
  end
end
```

- [ ] **Step 2: Create ActorEvent schema**

```elixir
# lib/population_simulator/simulation/actor_event.ex
defmodule PopulationSimulator.Simulation.ActorEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_events" do
    belongs_to :actor, PopulationSimulator.Actors.Actor
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    field :description, :string
    field :mood_impact, :string
    field :profile_effects, :string
    field :duration, :integer
    field :remaining, :integer
    field :active, :boolean, default: true
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :measure_id, :description, :mood_impact, :profile_effects, :duration, :remaining, :active])
    |> validate_required([:actor_id, :measure_id, :description, :mood_impact, :profile_effects, :duration, :remaining])
  end

  def new(actor_id, measure_id, description, mood_impact, profile_effects, duration) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      description: description,
      mood_impact: Jason.encode!(mood_impact),
      profile_effects: Jason.encode!(profile_effects),
      duration: duration,
      remaining: duration,
      active: true,
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
git add priv/repo/migrations/20260403300000_create_actor_events.exs lib/population_simulator/simulation/actor_event.ex
git commit -m "Add actor_events table and ActorEvent schema"
```

---

## Task 2: EventResponseValidator

**Files:**
- Create: `test/population_simulator/simulation/event_response_validator_test.exs`
- Create: `lib/population_simulator/simulation/event_response_validator.ex`

- [ ] **Step 1: Write failing tests**

```elixir
# test/population_simulator/simulation/event_response_validator_test.exs
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/event_response_validator_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement EventResponseValidator**

```elixir
# lib/population_simulator/simulation/event_response_validator.ex
defmodule PopulationSimulator.Simulation.EventResponseValidator do
  @moduledoc """
  Validates LLM-generated personal events.
  Mood impact capped +-2.0, profile_effects validated against allowed fields,
  income_delta capped +-70% of current income, duration clamped 1-6.
  """

  @max_mood_impact 2.0
  @max_income_ratio 0.7
  @max_duration 6
  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)
  @allowed_profile_fields ~w(employment_type employment_status income_delta has_dollars usd_savings_delta has_debt housing_type tenure has_bank_account has_credit_card)

  def validate(response, current_income) do
    with :ok <- validate_structure(response) do
      validated =
        response
        |> Map.update!("mood_impact", &clamp_mood_impact/1)
        |> Map.update!("profile_effects", &(filter_and_clamp_profile_effects(&1, current_income)))
        |> Map.update!("duration", &clamp_duration/1)

      {:ok, validated}
    end
  end

  defp validate_structure(response) do
    cond do
      not is_binary(response["event"]) or response["event"] == "" -> {:error, "missing event description"}
      not is_map(response["mood_impact"]) -> {:error, "missing mood_impact"}
      not is_map(response["profile_effects"]) -> {:error, "missing profile_effects"}
      not is_integer(response["duration"]) -> {:error, "missing or invalid duration"}
      true -> :ok
    end
  end

  defp clamp_mood_impact(impact) do
    Map.new(impact, fn {key, val} ->
      if key in @mood_dimensions do
        {key, clamp(val, -@max_mood_impact, @max_mood_impact)}
      else
        {key, val}
      end
    end)
  end

  defp filter_and_clamp_profile_effects(effects, current_income) do
    effects
    |> Map.take(@allowed_profile_fields)
    |> clamp_income_delta(current_income)
  end

  defp clamp_income_delta(effects, current_income) do
    case Map.get(effects, "income_delta") do
      nil -> effects
      delta when is_number(delta) ->
        max_delta = round(current_income * @max_income_ratio)
        clamped = delta |> max(-max_delta) |> min(max_delta)
        Map.put(effects, "income_delta", clamped)
      _ -> Map.delete(effects, "income_delta")
    end
  end

  defp clamp_duration(d) when is_integer(d), do: d |> max(1) |> min(@max_duration)
  defp clamp_duration(_), do: 3

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, _, _), do: 0.0
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/population_simulator/simulation/event_response_validator_test.exs`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/event_response_validator.ex test/population_simulator/simulation/event_response_validator_test.exs
git commit -m "Add EventResponseValidator with mood/profile clamping"
```

---

## Task 3: EventPromptBuilder

**Files:**
- Create: `lib/population_simulator/simulation/event_prompt_builder.ex`

- [ ] **Step 1: Implement EventPromptBuilder**

```elixir
# lib/population_simulator/simulation/event_prompt_builder.ex
defmodule PopulationSimulator.Simulation.EventPromptBuilder do
  @moduledoc """
  Builds per-actor prompt for generating a personal life event.
  """

  def build(profile, measure, mood, narrative, intentions) do
    narrative_section =
      if narrative && narrative != "" do
        "\n=== TU RELATO PERSONAL ===\n#{narrative}"
      else
        ""
      end

    intentions_section =
      if intentions && intentions != [] do
        items = Enum.map_join(intentions, "\n", fn i -> "- #{i}" end)
        "\n=== TUS INTENCIONES PENDIENTES ===\n#{items}"
      else
        ""
      end

    mood_section =
      if mood do
        """
        Confianza económica: #{mood.economic_confidence}/10
        Confianza gobierno: #{mood.government_trust}/10
        Bienestar: #{mood.personal_wellbeing}/10
        Enojo social: #{mood.social_anger}/10
        Perspectiva futuro: #{mood.future_outlook}/10
        """
      else
        ""
      end

    """
    Sos un narrador que genera un evento de vida para un ciudadano argentino del GBA.

    === PERFIL ===
    Edad: #{profile["age"]} | Sexo: #{profile["sex"]} | Estrato: #{profile["stratum"]}
    Zona: #{profile["zone"]} | Empleo: #{profile["employment_type"]}
    Estado laboral: #{profile["employment_status"]}
    Educación: #{profile["education_level"]}
    Ingreso: $#{profile["income"]}
    Vivienda: #{profile["housing_type"]} | Tenencia: #{profile["tenure"]}
    #{narrative_section}

    === HUMOR ACTUAL ===
    #{mood_section}
    #{intentions_section}

    === MEDIDA RECIENTE ===
    #{measure.title}: #{measure.description}

    === INSTRUCCIONES ===
    A este ciudadano le pasó algo esta semana. Puede ser consecuencia directa de la medida económica, o algo de su vida personal que no tiene nada que ver (problemas laborales, familiares, de salud, inseguridad, una buena noticia, etc.). Generá un evento realista y coherente con su perfil y situación.

    Respondé EXCLUSIVAMENTE con JSON válido:
    {
      "event": "<descripción del evento en 1-2 oraciones, en tercera persona>",
      "mood_impact": {
        "economic_confidence": <float -2.0 a 2.0>,
        "government_trust": <float -2.0 a 2.0>,
        "personal_wellbeing": <float -2.0 a 2.0>,
        "social_anger": <float -2.0 a 2.0>,
        "future_outlook": <float -2.0 a 2.0>
      },
      "profile_effects": {
        <campo>: <valor>
      },
      "duration": <int 1-6, cuántas medidas dura el impacto emocional>
    }

    REGLAS:
    - mood_impact: solo incluí dimensiones que cambian. Valores entre -2.0 y 2.0.
    - profile_effects: campos permitidos: employment_type, employment_status, income_delta, has_dollars, usd_savings_delta, has_debt, housing_type, tenure, has_bank_account, has_credit_card. Podés dejar vacío {} si no cambia nada del perfil.
    - income_delta es relativo al ingreso actual (no absoluto).
    - duration: 1-2 para eventos menores, 3-4 para eventos significativos, 5-6 para eventos que cambian la vida.
    - Todo en español.
    """
    |> String.trim()
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/event_prompt_builder.ex
git commit -m "Add EventPromptBuilder for personal life event generation"
```

---

## Task 4: EventDecayer

**Files:**
- Create: `test/population_simulator/simulation/event_decayer_test.exs`
- Create: `lib/population_simulator/simulation/event_decayer.ex`

- [ ] **Step 1: Write failing tests**

```elixir
# test/population_simulator/simulation/event_decayer_test.exs
defmodule PopulationSimulator.Simulation.EventDecayerTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.EventDecayer

  describe "decayed_impact/2" do
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/event_decayer_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement EventDecayer**

```elixir
# lib/population_simulator/simulation/event_decayer.ex
defmodule PopulationSimulator.Simulation.EventDecayer do
  @moduledoc """
  Decays active events: reduces remaining counter, deactivates expired,
  and computes decayed mood impact for prompt injection.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorEvent
  import Ecto.Query

  def decayed_impact(mood_impact, remaining, duration) when is_map(mood_impact) do
    ratio = if duration > 0, do: remaining / duration, else: 0.0

    Map.new(mood_impact, fn {key, val} ->
      {key, Float.round(val * ratio, 2)}
    end)
  end

  def aggregate_active_impacts(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      decayed = decayed_impact(event.mood_impact, event.remaining, event.duration)

      Map.merge(acc, decayed, fn _k, v1, v2 -> Float.round(v1 + v2, 2) end)
    end)
  end

  def tick_all do
    # Decrement remaining for all active events
    Repo.update_all(
      from(e in ActorEvent, where: e.active == true and e.remaining > 0),
      inc: [remaining: -1]
    )

    # Deactivate events where remaining hit 0
    Repo.update_all(
      from(e in ActorEvent, where: e.active == true and e.remaining <= 0),
      set: [active: false]
    )
  end

  def load_active_events(actor_id) do
    Repo.all(
      from(e in ActorEvent,
        where: e.actor_id == ^actor_id and e.active == true,
        order_by: [desc: e.inserted_at],
        limit: 3
      )
    )
    |> Enum.map(fn event ->
      %{
        description: event.description,
        mood_impact: Jason.decode!(event.mood_impact),
        profile_effects: Jason.decode!(event.profile_effects),
        duration: event.duration,
        remaining: event.remaining,
        inserted_at: event.inserted_at
      }
    end)
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/population_simulator/simulation/event_decayer_test.exs`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/event_decayer.ex test/population_simulator/simulation/event_decayer_test.exs
git commit -m "Add EventDecayer for event duration management and impact aggregation"
```

---

## Task 5: EventGenerator

**Files:**
- Create: `lib/population_simulator/simulation/event_generator.ex`

- [ ] **Step 1: Implement EventGenerator**

```elixir
# lib/population_simulator/simulation/event_generator.ex
defmodule PopulationSimulator.Simulation.EventGenerator do
  @moduledoc """
  Selects vulnerable actors and generates personalized life events via LLM.
  Runs after MeasureRunner + DissonanceCalculator each measure.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{
    ActorEvent,
    EventPromptBuilder,
    EventResponseValidator,
    EventDecayer,
    ActorMood,
    ActorSummary
  }
  alias PopulationSimulator.LLM.ClaudeClient

  import Ecto.Query
  require Logger

  @target_ratio 0.20

  def run(measure, actors, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 20)

    # Decay existing events first
    EventDecayer.tick_all()

    # Select ~20% of actors weighted by vulnerability
    selected = select_vulnerable(actors)
    total = length(selected)

    Logger.info("Event generation: #{total} actors selected for measure #{measure.id}")

    results =
      selected
      |> Task.async_stream(
        fn actor -> generate_event(actor, measure) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0}, fn
        {:ok, {:ok, _}}, acc -> %{acc | ok: acc.ok + 1}
        _, acc -> %{acc | error: acc.error + 1}
      end)

    Logger.info("Events complete: #{results.ok}/#{total} OK, #{results.error} errors")
    results
  end

  defp select_vulnerable(actors) do
    scored =
      actors
      |> Enum.map(fn actor ->
        mood = load_latest_mood(actor.id)
        dissonance = load_latest_dissonance(actor.id)
        score = vulnerability_score(actor, mood, dissonance)
        {actor, score}
      end)

    total_score = scored |> Enum.map(fn {_, s} -> s end) |> Enum.sum()
    target_count = round(length(actors) * @target_ratio)

    if total_score <= 0 do
      Enum.take_random(actors, target_count)
    else
      scored
      |> Enum.sort_by(fn {_, s} -> -s end)
      |> Enum.take(target_count)
      |> Enum.map(fn {actor, _} -> actor end)
    end
  end

  defp vulnerability_score(actor, mood, dissonance) do
    stratum = actor.profile["stratum"] || "middle"
    employment = actor.profile["employment_status"] || "employed"

    economic = if mood, do: (10 - mood.economic_confidence) / 10, else: 0.5
    anger = if mood, do: mood.social_anger / 10, else: 0.5
    unemployed_bonus = if employment == "unemployed", do: 0.3, else: 0.0
    poverty_bonus = if stratum in ["destitute", "low"], do: 0.2, else: 0.0

    economic + anger + unemployed_bonus + poverty_bonus + (dissonance || 0.0)
  end

  defp generate_event(actor, measure) do
    mood = load_latest_mood(actor.id)
    narrative = load_narrative(actor.id)
    intentions = load_pending_intentions(actor.id)
    current_income = actor.profile["income"] || 0

    prompt = EventPromptBuilder.build(actor.profile, measure, mood, narrative, intentions)

    case ClaudeClient.complete_raw(prompt, max_tokens: 512, temperature: 0.5, receive_timeout: 30_000) do
      {:ok, response} ->
        case EventResponseValidator.validate(response, current_income) do
          {:ok, validated} ->
            persist_event(actor, measure.id, validated)
            apply_immediate_effects(actor, validated)
            {:ok, actor.id}

          {:error, reason} ->
            Logger.warning("Event validation failed for actor #{actor.id}: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Event LLM call failed for actor #{actor.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp persist_event(actor, measure_id, validated) do
    # Enforce max 3 active events — deactivate oldest if needed
    active_count =
      Repo.one(from(e in ActorEvent, where: e.actor_id == ^actor.id and e.active == true, select: count(e.id)))

    if active_count >= 3 do
      oldest =
        Repo.one(from(e in ActorEvent, where: e.actor_id == ^actor.id and e.active == true, order_by: [asc: e.inserted_at], limit: 1))

      if oldest do
        Repo.update_all(from(e in ActorEvent, where: e.id == ^oldest.id), set: [active: false])
      end
    end

    row = ActorEvent.new(
      actor.id,
      measure_id,
      validated["event"],
      validated["mood_impact"],
      validated["profile_effects"],
      validated["duration"]
    )

    Repo.insert_all(ActorEvent, [row])
  end

  defp apply_immediate_effects(actor, validated) do
    # Apply mood impact as a new mood snapshot
    mood_impact = validated["mood_impact"]

    if map_size(mood_impact) > 0 do
      current = load_latest_mood(actor.id)

      if current do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        new_mood = %{
          id: Ecto.UUID.generate(),
          actor_id: actor.id,
          measure_id: nil,
          decision_id: nil,
          economic_confidence: clamp_mood(current.economic_confidence + Map.get(mood_impact, "economic_confidence", 0)),
          government_trust: clamp_mood(current.government_trust + Map.get(mood_impact, "government_trust", 0)),
          personal_wellbeing: clamp_mood(current.personal_wellbeing + Map.get(mood_impact, "personal_wellbeing", 0)),
          social_anger: clamp_mood(current.social_anger + Map.get(mood_impact, "social_anger", 0)),
          future_outlook: clamp_mood(current.future_outlook + Map.get(mood_impact, "future_outlook", 0)),
          narrative: current.narrative,
          inserted_at: now,
          updated_at: now
        }

        Repo.insert_all(ActorMood, [new_mood])
      end
    end

    # Apply profile effects (update actor profile JSON)
    profile_effects = validated["profile_effects"]

    if map_size(profile_effects) > 0 do
      current_profile = actor.profile
      income = current_profile["income"] || 0

      updated_profile =
        Enum.reduce(profile_effects, current_profile, fn
          {"income_delta", delta}, p when is_number(delta) ->
            Map.put(p, "income", max(round(income + delta), 0))
          {"usd_savings_delta", delta}, p when is_number(delta) ->
            current_usd = p["usd_savings"] || 0
            Map.put(p, "usd_savings", max(round(current_usd + delta), 0))
          {key, value}, p ->
            Map.put(p, key, value)
        end)

      Repo.update_all(
        from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor.id),
        set: [profile: updated_profile]
      )
    end
  end

  defp load_latest_mood(actor_id) do
    Repo.one(
      from(m in ActorMood,
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    )
  end

  defp load_latest_dissonance(actor_id) do
    Repo.one(
      from(d in PopulationSimulator.Simulation.Decision,
        where: d.actor_id == ^actor_id and not is_nil(d.dissonance),
        order_by: [desc: d.inserted_at],
        limit: 1,
        select: d.dissonance
      )
    )
  end

  defp load_narrative(actor_id) do
    case Repo.one(
      from(s in ActorSummary,
        where: s.actor_id == ^actor_id,
        order_by: [desc: s.version],
        limit: 1,
        select: s.narrative
      )
    ) do
      nil -> nil
      narrative -> narrative
    end
  end

  defp load_pending_intentions(_actor_id), do: []

  defp clamp_mood(val), do: val |> round() |> max(1) |> min(10)
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/event_generator.ex
git commit -m "Add EventGenerator for LLM-powered personal life events"
```

---

## Task 6: Prompt injection + sim.run integration

**Files:**
- Modify: `lib/population_simulator/simulation/consciousness_loader.ex`
- Modify: `lib/population_simulator/simulation/prompt_builder.ex`
- Modify: `lib/mix/tasks/sim.run.ex`

- [ ] **Step 1: Add event loading to ConsciousnessLoader**

In `consciousness_loader.ex`, add to the `load/1` return map:

```elixir
    active_events = load_active_events(actor_id)
```

And include `events: active_events` in the returned map. Add the helper:

```elixir
  defp load_active_events(actor_id) do
    PopulationSimulator.Simulation.EventDecayer.load_active_events(actor_id)
  end
```

- [ ] **Step 2: Add events block to PromptBuilder build/5**

In `prompt_builder.ex`, in the `build_consciousness_block/1` function, add an events section:

```elixir
    events_text =
      case consciousness[:events] do
        nil -> ""
        [] -> ""
        events ->
          items = Enum.map_join(events, "\n", fn e ->
            ago = e.duration - e.remaining
            time = if ago == 0, do: "Esta semana", else: "Hace #{ago} medida(s)"
            decay = if e.remaining < e.duration, do: " (impacto decayendo)", else: ""
            "- #{time}: #{e.description}#{decay}"
          end)
          "\n\n=== EVENTOS RECIENTES EN TU VIDA ===\n#{items}"
      end
```

Then append `#{events_text}` to the consciousness block output, before the closing newlines.

- [ ] **Step 3: Add EventGenerator call to sim.run**

In `lib/mix/tasks/sim.run.ex`, inside the `if Keyword.get(parsed, :cafe, false)` block, after `MeasureRunner.run` completes and before `CafeRunner.run`, add:

```elixir
        IO.puts("\nGenerating personal events...")
        event_results = PopulationSimulator.Simulation.EventGenerator.run(measure, actors, concurrency: concurrency)
        IO.puts("Events: #{event_results.ok} generated, #{event_results.error} errors")
```

- [ ] **Step 4: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/consciousness_loader.ex lib/population_simulator/simulation/prompt_builder.ex lib/mix/tasks/sim.run.ex
git commit -m "Inject active events into prompts and wire EventGenerator into sim.run --cafe"
```

---

## Task 7: CLAUDE.md + README docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add events documentation**

In the Key design decisions section, after the cognitive dissonance bullet, add:

```markdown
- **Personal events**: EventGenerator selects ~20% of actors per measure (weighted by vulnerability: low stratum, high anger, unemployed, high dissonance). LLM generates a personalized event per actor — can be measure-derived or a life event. Events modify mood and profile (employment, income, etc.) and decay over 1-6 measures. Max 3 active events per actor. EventDecayer ticks remaining counter each measure.
```

In Core Modules table add:

```markdown
| `EventGenerator` | Select vulnerable actors, generate personal events via LLM |
| `EventDecayer` | Decay event duration, compute aggregate mood impact |
| `EventResponseValidator` | Validate event LLM response: mood +-2.0, profile fields, duration 1-6 |
```

In Database Schema tables add:

```markdown
- **actor_events** — personal life events with mood impact, profile effects, and decay duration
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document personal events system in CLAUDE.md"
```
