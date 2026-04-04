# Layer 1: Intentions with Agency — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Actors generate free-form intentions during introspection ("voy a buscar trabajo", "voy a comprar dólares"). The LLM resolves them in the next introspection, and profile effects are applied to the actor (employment changes, income deltas, etc.).

**Architecture:** Intentions are generated as part of the IntrospectionRunner output. IntentionExecutor applies profile_effects from resolved intentions. ConsciousnessLoader provides pending intentions to prompts so actors maintain continuity. Max 2 active intentions per actor.

**Tech Stack:** Elixir/Ecto, SQLite3.

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `priv/repo/migrations/20260403600000_create_actor_intentions.exs` | actor_intentions table |
| `lib/population_simulator/simulation/actor_intention.ex` | Ecto schema |
| `lib/population_simulator/simulation/intention_executor.ex` | Apply profile effects, expire old intentions |
| `test/population_simulator/simulation/intention_executor_test.exs` | Unit tests |

### Modified files

| File | Change |
|------|--------|
| `lib/population_simulator/simulation/introspection_prompt_builder.ex` | Request intentions + resolutions in output |
| `lib/population_simulator/simulation/introspection_runner.ex` | Persist intentions, call IntentionExecutor |
| `lib/population_simulator/simulation/consciousness_loader.ex` | Load pending intentions |
| `lib/population_simulator/simulation/prompt_builder.ex` | Add intentions block |
| `lib/population_simulator/simulation/event_generator.ex` | Load real pending intentions (replace stub) |

---

## Task 1: Migration + Schema

**Files:**
- Create: `priv/repo/migrations/20260403600000_create_actor_intentions.exs`
- Create: `lib/population_simulator/simulation/actor_intention.ex`

- [ ] **Step 1: Create migration**

```elixir
# priv/repo/migrations/20260403600000_create_actor_intentions.exs
defmodule PopulationSimulator.Repo.Migrations.CreateActorIntentions do
  use Ecto.Migration

  def change do
    create table(:actor_intentions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :description, :text, null: false
      add :profile_effects, :text, null: false
      add :urgency, :string, null: false, default: "medium"
      add :status, :string, null: false, default: "pending"
      add :resolved_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:actor_intentions, [:actor_id])
    create index(:actor_intentions, [:actor_id, :status])
  end
end
```

- [ ] **Step 2: Create ActorIntention schema**

```elixir
# lib/population_simulator/simulation/actor_intention.ex
defmodule PopulationSimulator.Simulation.ActorIntention do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_intentions" do
    belongs_to :actor, PopulationSimulator.Actors.Actor
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    field :description, :string
    field :profile_effects, :string
    field :urgency, :string, default: "medium"
    field :status, :string, default: "pending"
    field :resolved_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(intention, attrs) do
    intention
    |> cast(attrs, [:actor_id, :measure_id, :description, :profile_effects, :urgency, :status, :resolved_at])
    |> validate_required([:actor_id, :measure_id, :description, :profile_effects, :urgency, :status])
    |> validate_inclusion(:status, ["pending", "executed", "frustrated", "expired"])
    |> validate_inclusion(:urgency, ["high", "medium", "low"])
  end

  def new(actor_id, measure_id, description, profile_effects, urgency) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      description: description,
      profile_effects: Jason.encode!(profile_effects),
      urgency: urgency || "medium",
      status: "pending",
      resolved_at: nil,
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
git add priv/repo/migrations/20260403600000_create_actor_intentions.exs lib/population_simulator/simulation/actor_intention.ex
git commit -m "Add actor_intentions table and ActorIntention schema"
```

---

## Task 2: IntentionExecutor

**Files:**
- Create: `test/population_simulator/simulation/intention_executor_test.exs`
- Create: `lib/population_simulator/simulation/intention_executor.ex`

- [ ] **Step 1: Write failing tests**

```elixir
# test/population_simulator/simulation/intention_executor_test.exs
defmodule PopulationSimulator.Simulation.IntentionExecutorTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.IntentionExecutor

  @allowed_fields ~w(employment_type employment_status income_delta has_dollars usd_savings_delta has_debt housing_type tenure has_bank_account has_credit_card)

  describe "validate_profile_effects/2" do
    test "passes through allowed fields" do
      effects = %{"employment_type" => "formal_employee", "income_delta" => 100_000}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      assert result["employment_type"] == "formal_employee"
      assert result["income_delta"] == 100_000
    end

    test "strips unrecognized fields" do
      effects = %{"employment_type" => "formal", "superpower" => "fly"}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      refute Map.has_key?(result, "superpower")
    end

    test "clamps income_delta to +-50% of current income" do
      effects = %{"income_delta" => 400_000}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      assert result["income_delta"] == 250_000
    end

    test "clamps negative income_delta" do
      effects = %{"income_delta" => -400_000}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      assert result["income_delta"] == -250_000
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/intention_executor_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement IntentionExecutor**

```elixir
# lib/population_simulator/simulation/intention_executor.ex
defmodule PopulationSimulator.Simulation.IntentionExecutor do
  @moduledoc """
  Applies profile effects from resolved intentions and expires old ones.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorIntention
  import Ecto.Query

  @allowed_fields ~w(employment_type employment_status income_delta has_dollars usd_savings_delta has_debt housing_type tenure has_bank_account has_credit_card)
  @max_income_ratio 0.5
  @max_active 2

  def execute_resolutions(actor_id, resolutions) when is_list(resolutions) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(resolutions, fn resolution ->
      status = resolution["status"]
      description = resolution["description"]

      if status in ["executed", "frustrated"] do
        # Find matching pending intention
        intention = Repo.one(
          from(i in ActorIntention,
            where: i.actor_id == ^actor_id and i.status == "pending",
            where: like(i.description, ^"%#{String.slice(description || "", 0, 30)}%"),
            order_by: [desc: i.inserted_at],
            limit: 1
          )
        )

        if intention do
          Repo.update_all(
            from(i in ActorIntention, where: i.id == ^intention.id),
            set: [status: status, resolved_at: now]
          )

          if status == "executed" do
            apply_profile_effects(actor_id, intention)
          end
        end
      end
    end)
  end

  def persist_new_intentions(actor_id, measure_id, intentions) when is_list(intentions) do
    # Count current pending
    pending_count = Repo.one(
      from(i in ActorIntention, where: i.actor_id == ^actor_id and i.status == "pending", select: count(i.id))
    ) || 0

    available_slots = max(@max_active - pending_count, 0)

    intentions
    |> Enum.take(available_slots)
    |> Enum.each(fn intention ->
      current_income = load_actor_income(actor_id)
      effects = validate_profile_effects(intention["profile_effects"] || %{}, current_income)

      row = ActorIntention.new(
        actor_id,
        measure_id,
        intention["description"] || "",
        effects,
        intention["urgency"] || "medium"
      )

      Repo.insert_all(ActorIntention, [row])
    end)
  end

  def expire_old_intentions(actor_id, introspection_count) do
    # Expire pending intentions older than 2 introspections
    if introspection_count >= 2 do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.update_all(
        from(i in ActorIntention,
          where: i.actor_id == ^actor_id and i.status == "pending",
          where: i.inserted_at < ago(^(introspection_count * 3), "day")
        ),
        set: [status: "expired", resolved_at: now]
      )
    end
  end

  def load_pending(actor_id) do
    Repo.all(
      from(i in ActorIntention,
        where: i.actor_id == ^actor_id and i.status == "pending",
        order_by: [desc: i.inserted_at],
        limit: @max_active
      )
    )
    |> Enum.map(fn i ->
      %{
        description: i.description,
        urgency: i.urgency,
        inserted_at: i.inserted_at
      }
    end)
  end

  def validate_profile_effects(effects, current_income) when is_map(effects) do
    effects
    |> Map.take(@allowed_fields)
    |> clamp_income_delta(current_income)
  end

  def validate_profile_effects(_, _), do: %{}

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

  defp apply_profile_effects(actor_id, intention) do
    effects = Jason.decode!(intention.profile_effects)

    if map_size(effects) > 0 do
      actor = Repo.one(from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor_id))

      if actor do
        current_profile = actor.profile
        income = current_profile["income"] || 0

        updated_profile =
          Enum.reduce(effects, current_profile, fn
            {"income_delta", delta}, p when is_number(delta) ->
              Map.put(p, "income", max(round(income + delta), 0))
            {"usd_savings_delta", delta}, p when is_number(delta) ->
              current_usd = p["usd_savings"] || 0
              Map.put(p, "usd_savings", max(round(current_usd + delta), 0))
            {key, value}, p ->
              Map.put(p, key, value)
          end)

        Repo.update_all(
          from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor_id),
          set: [profile: updated_profile]
        )
      end
    end
  end

  defp load_actor_income(actor_id) do
    case Repo.one(from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor_id, select: a.profile)) do
      nil -> 0
      profile -> profile["income"] || 0
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/population_simulator/simulation/intention_executor_test.exs`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/intention_executor.ex test/population_simulator/simulation/intention_executor_test.exs
git commit -m "Add IntentionExecutor for resolving intentions and applying profile effects"
```

---

## Task 3: IntrospectionRunner + IntrospectionPromptBuilder modifications

**Files:**
- Modify: `lib/population_simulator/simulation/introspection_prompt_builder.ex`
- Modify: `lib/population_simulator/simulation/introspection_runner.ex`

- [ ] **Step 1: Update IntrospectionPromptBuilder**

Read `introspection_prompt_builder.ex`. The current `build/6` takes (profile, narrative, decisions, cafes, mood, dissonance_data). We need to add intentions as a 7th parameter.

Add `build/7`:

```elixir
  def build(profile, previous_narrative, decisions, cafe_summaries, current_mood, dissonance_data, pending_intentions) do
    base = build(profile, previous_narrative, decisions, cafe_summaries, current_mood, dissonance_data)

    intentions_block = build_intentions_block(pending_intentions)

    if intentions_block != "" do
      String.replace(base, "=== INSTRUCCIONES ===", "#{intentions_block}\n=== INSTRUCCIONES ===")
    else
      base
    end
  end

  defp build_intentions_block(nil), do: ""
  defp build_intentions_block([]), do: ""

  defp build_intentions_block(intentions) do
    items = Enum.map_join(intentions, "\n", fn i ->
      "- \"#{i.description}\" (urgencia: #{i.urgency})"
    end)

    """
    === TUS INTENCIONES PENDIENTES ===
    #{items}
    ¿Se cumplieron, se frustraron, o siguen pendientes? Reflexioná sobre esto.
    """
  end
```

Also update the INSTRUCCIONES section in `build/5` (the base) to request intentions and resolutions in the JSON output:

In the JSON format section, add after `"self_observations"`:

```
      "intentions": [
        {"description": "<qué vas a hacer>", "profile_effects": {<campos que cambian>}, "urgency": "high|medium|low"}
      ],
      "intention_resolutions": [
        {"description": "<intención previa>", "status": "executed|frustrated|pending", "reflection": "<reflexión>"}
      ]
```

And in REGLAS add:
```
    - intentions: máximo 2 intenciones nuevas. Campos permitidos en profile_effects: employment_type, employment_status, income_delta, has_dollars, usd_savings_delta, has_debt, housing_type, tenure, has_bank_account, has_credit_card.
    - intention_resolutions: solo para intenciones pendientes que te presenté. Si no hay intenciones pendientes, devolvé array vacío.
```

- [ ] **Step 2: Update IntrospectionRunner**

Read `introspection_runner.ex`. In `introspect_actor/2`:

1. Load pending intentions:
```elixir
    pending_intentions = PopulationSimulator.Simulation.IntentionExecutor.load_pending(actor.id)
```

2. Call `build/7` instead of `build/6`:
```elixir
    prompt = IntrospectionPromptBuilder.build(
      actor.profile,
      previous_narrative,
      decisions,
      cafe_summaries,
      current_mood,
      dissonance_data,
      pending_intentions
    )
```

3. After persisting the summary, handle intentions:
```elixir
        # Process intention resolutions
        resolutions = response["intention_resolutions"] || []
        IntentionExecutor.execute_resolutions(actor.id, resolutions)

        # Persist new intentions
        new_intentions = response["intentions"] || []
        IntentionExecutor.persist_new_intentions(actor.id, measure.id, new_intentions)

        # Expire old ones
        IntentionExecutor.expire_old_intentions(actor.id, version)
```

Add alias:
```elixir
  alias PopulationSimulator.Simulation.IntentionExecutor
```

- [ ] **Step 3: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator/simulation/introspection_prompt_builder.ex lib/population_simulator/simulation/introspection_runner.ex
git commit -m "Add intentions to introspection: generation, resolution, and profile effects"
```

---

## Task 4: Prompt injection + EventGenerator fix

**Files:**
- Modify: `lib/population_simulator/simulation/consciousness_loader.ex`
- Modify: `lib/population_simulator/simulation/prompt_builder.ex`
- Modify: `lib/population_simulator/simulation/event_generator.ex`

- [ ] **Step 1: Load intentions in ConsciousnessLoader**

Add to `load/1` return map:
```elixir
    intentions = load_pending_intentions(actor_id)
```

Add helper:
```elixir
  defp load_pending_intentions(actor_id) do
    PopulationSimulator.Simulation.IntentionExecutor.load_pending(actor_id)
  end
```

Include `intentions: intentions` in the returned map.

- [ ] **Step 2: Add intentions block to PromptBuilder**

In `build_consciousness_block/1`, add:

```elixir
    intentions_text =
      case consciousness[:intentions] do
        nil -> ""
        [] -> ""
        intentions ->
          items = Enum.map_join(intentions, "\n", fn i ->
            "- #{i.description} (urgencia: #{i.urgency})"
          end)
          "\n\n=== TUS INTENCIONES ===\n#{items}"
      end
```

Append to the consciousness block output.

- [ ] **Step 3: Fix EventGenerator stub**

In `event_generator.ex`, replace the stub `load_pending_intentions/1`:

```elixir
  defp load_pending_intentions(actor_id) do
    PopulationSimulator.Simulation.IntentionExecutor.load_pending(actor_id)
    |> Enum.map(fn i -> i.description end)
  end
```

- [ ] **Step 4: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator/simulation/consciousness_loader.ex lib/population_simulator/simulation/prompt_builder.ex lib/population_simulator/simulation/event_generator.ex
git commit -m "Inject intentions into prompts and wire EventGenerator to real intention data"
```

---

## Task 5: CLAUDE.md docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add intentions documentation**

After the theory of mind bullet:

```markdown
- **Intentions**: During introspection, actors generate free-form intentions (max 2 active). The LLM decides the action and profile_effects (employment, income, dollars, etc.). In the next introspection, the LLM resolves pending intentions (executed/frustrated). IntentionExecutor validates effects against allowed fields, clamps income_delta to +-50%, and applies changes to the actor profile. Intentions expire after 2 introspections without resolution.
```

In Core Modules table:
```markdown
| `IntentionExecutor` | Apply profile effects from resolved intentions, validate, expire |
```

In Database Schema:
```markdown
- **actor_intentions** — free-form intentions with profile effects, urgency, and resolution status
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document intentions system in CLAUDE.md"
```
