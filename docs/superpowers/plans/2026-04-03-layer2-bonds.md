# Layer 2: Emergent Social Bonds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Actors who share 3+ cafés form persistent social bonds. Bonds influence café seating (bonded actors tend to sit together) and are annotated in café prompts for richer dialogue with history.

**Architecture:** AffinityTracker runs after each café round, upserting bond records between participants. CafeGrouper is modified to prefer seating bonded actors together. CafePromptBuilder annotates bonds in participant sections. Bond affinity decays without reinforcement and bonds are deleted at zero.

**Tech Stack:** Elixir/Ecto, SQLite3.

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `priv/repo/migrations/20260403400000_create_actor_bonds.exs` | actor_bonds table |
| `lib/population_simulator/simulation/actor_bond.ex` | Ecto schema |
| `lib/population_simulator/simulation/affinity_tracker.ex` | Update bonds after each café |
| `test/population_simulator/simulation/affinity_tracker_test.exs` | Unit tests |

### Modified files

| File | Change |
|------|--------|
| `lib/population_simulator/simulation/cafe_grouper.ex` | Prefer bonded actors in same table |
| `lib/population_simulator/simulation/cafe_prompt_builder.ex` | Annotate bonds in participant section |
| `lib/population_simulator/simulation/cafe_runner.ex` | Call AffinityTracker after persisting café |

---

## Task 1: Migration + Schema

**Files:**
- Create: `priv/repo/migrations/20260403400000_create_actor_bonds.exs`
- Create: `lib/population_simulator/simulation/actor_bond.ex`

- [ ] **Step 1: Create migration**

```elixir
# priv/repo/migrations/20260403400000_create_actor_bonds.exs
defmodule PopulationSimulator.Repo.Migrations.CreateActorBonds do
  use Ecto.Migration

  def change do
    create table(:actor_bonds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_a_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_b_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :affinity, :float, null: false, default: 0.1
      add :shared_cafes, :integer, null: false, default: 1
      add :formed_at, :utc_datetime
      add :last_cafe_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:actor_bonds, [:actor_a_id, :actor_b_id])
    create index(:actor_bonds, [:actor_a_id])
    create index(:actor_bonds, [:actor_b_id])
  end
end
```

- [ ] **Step 2: Create ActorBond schema**

```elixir
# lib/population_simulator/simulation/actor_bond.ex
defmodule PopulationSimulator.Simulation.ActorBond do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_bonds" do
    belongs_to :actor_a, PopulationSimulator.Actors.Actor
    belongs_to :actor_b, PopulationSimulator.Actors.Actor
    field :affinity, :float, default: 0.1
    field :shared_cafes, :integer, default: 1
    field :formed_at, :utc_datetime
    field :last_cafe_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(bond, attrs) do
    bond
    |> cast(attrs, [:actor_a_id, :actor_b_id, :affinity, :shared_cafes, :formed_at, :last_cafe_at])
    |> validate_required([:actor_a_id, :actor_b_id, :affinity, :shared_cafes, :last_cafe_at])
    |> unique_constraint([:actor_a_id, :actor_b_id])
  end

  def ordered_pair(id1, id2) when id1 < id2, do: {id1, id2}
  def ordered_pair(id1, id2), do: {id2, id1}
end
```

- [ ] **Step 3: Run migration and tests**

Run: `mix ecto.migrate && mix test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/20260403400000_create_actor_bonds.exs lib/population_simulator/simulation/actor_bond.ex
git commit -m "Add actor_bonds table and ActorBond schema"
```

---

## Task 2: AffinityTracker

**Files:**
- Create: `test/population_simulator/simulation/affinity_tracker_test.exs`
- Create: `lib/population_simulator/simulation/affinity_tracker.ex`

- [ ] **Step 1: Write failing tests**

```elixir
# test/population_simulator/simulation/affinity_tracker_test.exs
defmodule PopulationSimulator.Simulation.AffinityTrackerTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.AffinityTracker

  describe "pairs_from_table/1" do
    test "generates all unique ordered pairs" do
      actor_ids = ["c", "a", "b"]
      pairs = AffinityTracker.pairs_from_table(actor_ids)

      assert length(pairs) == 3
      assert {"a", "b"} in pairs
      assert {"a", "c"} in pairs
      assert {"b", "c"} in pairs
    end

    test "single actor produces no pairs" do
      assert AffinityTracker.pairs_from_table(["a"]) == []
    end

    test "two actors produce one pair" do
      pairs = AffinityTracker.pairs_from_table(["b", "a"])
      assert pairs == [{"a", "b"}]
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/population_simulator/simulation/affinity_tracker_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement AffinityTracker**

```elixir
# lib/population_simulator/simulation/affinity_tracker.ex
defmodule PopulationSimulator.Simulation.AffinityTracker do
  @moduledoc """
  Updates social bonds between actors after each café round.
  Bonds form when shared_cafes >= 3. Affinity decays without reinforcement.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorBond
  import Ecto.Query

  @affinity_increment 0.15
  @max_affinity 1.0
  @formation_threshold 3
  @decay_rate 0.1
  @max_bonds_per_actor 10

  def update_from_cafe(table_actor_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    pairs = pairs_from_table(table_actor_ids)

    Enum.each(pairs, fn {a_id, b_id} ->
      upsert_bond(a_id, b_id, now)
    end)
  end

  def decay_inactive_bonds(current_measure_id) do
    # Decay all bonds not updated in this measure cycle
    all_bonds = Repo.all(from(b in ActorBond))

    Enum.each(all_bonds, fn bond ->
      new_affinity = Float.round(bond.affinity - @decay_rate, 2)

      if new_affinity <= 0 do
        Repo.delete(bond)
      else
        Repo.update_all(
          from(b in ActorBond, where: b.id == ^bond.id),
          set: [affinity: new_affinity]
        )
      end
    end)
  end

  def load_bonds_for_actor(actor_id) do
    Repo.all(
      from(b in ActorBond,
        where: (b.actor_a_id == ^actor_id or b.actor_b_id == ^actor_id) and not is_nil(b.formed_at),
        select: %{
          partner_id: fragment("CASE WHEN ? = ? THEN ? ELSE ? END", b.actor_a_id, ^actor_id, b.actor_b_id, b.actor_a_id),
          affinity: b.affinity,
          shared_cafes: b.shared_cafes
        }
      )
    )
  end

  def load_bonds_between(actor_ids) do
    pairs = pairs_from_table(actor_ids)

    Enum.flat_map(pairs, fn {a_id, b_id} ->
      case Repo.one(from(b in ActorBond,
        where: b.actor_a_id == ^a_id and b.actor_b_id == ^b_id and not is_nil(b.formed_at)
      )) do
        nil -> []
        bond -> [{a_id, b_id, bond.shared_cafes}]
      end
    end)
  end

  def pairs_from_table(actor_ids) do
    sorted = Enum.sort(actor_ids)

    for {a, i} <- Enum.with_index(sorted),
        b <- Enum.slice(sorted, (i + 1)..-1//1) do
      {a, b}
    end
  end

  defp upsert_bond(a_id, b_id, now) do
    # Check bond count for both actors
    a_count = bond_count(a_id)
    b_count = bond_count(b_id)

    existing = Repo.one(from(b in ActorBond, where: b.actor_a_id == ^a_id and b.actor_b_id == ^b_id))

    case existing do
      nil ->
        if a_count < @max_bonds_per_actor and b_count < @max_bonds_per_actor do
          Repo.insert_all(ActorBond, [%{
            id: Ecto.UUID.generate(),
            actor_a_id: a_id,
            actor_b_id: b_id,
            affinity: 0.1,
            shared_cafes: 1,
            formed_at: nil,
            last_cafe_at: now,
            inserted_at: now,
            updated_at: now
          }], on_conflict: :nothing)
        end

      bond ->
        new_affinity = min(bond.affinity + @affinity_increment, @max_affinity)
        new_shared = bond.shared_cafes + 1
        formed = if new_shared >= @formation_threshold and is_nil(bond.formed_at), do: now, else: bond.formed_at

        Repo.update_all(
          from(b in ActorBond, where: b.id == ^bond.id),
          set: [
            affinity: Float.round(new_affinity, 2),
            shared_cafes: new_shared,
            formed_at: formed,
            last_cafe_at: now,
            updated_at: now
          ]
        )
    end
  end

  defp bond_count(actor_id) do
    Repo.one(from(b in ActorBond,
      where: b.actor_a_id == ^actor_id or b.actor_b_id == ^actor_id,
      select: count(b.id)
    )) || 0
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/population_simulator/simulation/affinity_tracker_test.exs`
Expected: Pass.

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add lib/population_simulator/simulation/affinity_tracker.ex test/population_simulator/simulation/affinity_tracker_test.exs
git commit -m "Add AffinityTracker for emergent social bonds"
```

---

## Task 3: CafeGrouper bond-aware seating

**Files:**
- Modify: `lib/population_simulator/simulation/cafe_grouper.ex`

- [ ] **Step 1: Read current CafeGrouper**

Read `lib/population_simulator/simulation/cafe_grouper.ex` to understand the current grouping logic.

- [ ] **Step 2: Add bond-aware seating**

Modify the `split_large_group/2` function to prefer placing bonded actors together instead of random shuffle. The approach:

1. Load bonds between actors in the group
2. Build clusters around bonded pairs
3. Fill remaining seats with unbonded actors
4. If no bonds exist, fall back to current shuffle behavior

Add at the top of the module:
```elixir
  alias PopulationSimulator.Simulation.AffinityTracker
```

Replace the `split_large_group` for large groups:

```elixir
  defp split_large_group(key, actors) when length(actors) <= @max_table_size do
    [{key, actors}]
  end

  defp split_large_group(key, actors) do
    actor_ids = Enum.map(actors, fn a -> a.id end)
    bonds = AffinityTracker.load_bonds_between(actor_ids)
    actor_map = Map.new(actors, fn a -> {a.id, a} end)

    if bonds == [] do
      # No bonds — shuffle as before
      actors
      |> Enum.shuffle()
      |> Enum.chunk_every(@max_table_size)
      |> Enum.with_index()
      |> Enum.map(fn {chunk, idx} ->
        sub_key = if idx == 0, do: key, else: "#{key}:#{idx}"
        {sub_key, chunk}
      end)
    else
      # Build tables preferring bonded actors together
      tables = build_bonded_tables(actors, bonds, actor_map)
      tables
      |> Enum.with_index()
      |> Enum.map(fn {table, idx} ->
        sub_key = if idx == 0, do: key, else: "#{key}:#{idx}"
        {sub_key, table}
      end)
    end
  end

  defp build_bonded_tables(actors, bonds, actor_map) do
    # Group bonded actors into clusters
    bonded_ids = bonds |> Enum.flat_map(fn {a, b, _} -> [a, b] end) |> MapSet.new()
    unbonded = Enum.reject(actors, fn a -> MapSet.member?(bonded_ids, a.id) end) |> Enum.shuffle()
    bonded = Enum.filter(actors, fn a -> MapSet.member?(bonded_ids, a.id) end) |> Enum.shuffle()

    # Start tables with bonded actors, fill with unbonded
    all = bonded ++ unbonded
    Enum.chunk_every(all, @max_table_size)
  end
```

- [ ] **Step 3: Run tests**

Run: `mix test test/population_simulator/simulation/cafe_grouper_test.exs && mix test`
Expected: All pass. Existing tests still work (they have no bonds in DB).

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator/simulation/cafe_grouper.ex
git commit -m "Add bond-aware seating to CafeGrouper"
```

---

## Task 4: CafePromptBuilder bond annotations + CafeRunner integration

**Files:**
- Modify: `lib/population_simulator/simulation/cafe_prompt_builder.ex`
- Modify: `lib/population_simulator/simulation/cafe_runner.ex`

- [ ] **Step 1: Annotate bonds in CafePromptBuilder**

Read `cafe_prompt_builder.ex`. Modify the `build/2` function to accept an optional third parameter for bonds:

```elixir
  def build(measure, participants, bonds \\ [])
```

In `participant_section/2`, change to `participant_section/3` accepting bonds. If the participant has a bond with another participant, annotate it:

```elixir
  defp participant_section(participant, names, bonds) do
    name = Map.get(names, participant.actor_id, "Vecino")
    # ... existing profile/decision/mood code ...

    bond_text =
      bonds
      |> Enum.filter(fn {a, b, _} -> a == participant.actor_id or b == participant.actor_id end)
      |> Enum.map(fn {a, b, shared} ->
        partner_id = if a == participant.actor_id, do: b, else: a
        partner_name = Map.get(names, partner_id, "vecino")
        "vínculo con #{partner_name}, #{shared} cafés juntos"
      end)
      |> Enum.join(", ")

    bond_annotation = if bond_text != "", do: " [#{bond_text}]", else: ""

    # Prepend to the first line: "--- María (ID: uuid) [vínculo con Jorge, 5 cafés juntos] ---"
    # Adjust the header line to include bond_annotation
  end
```

- [ ] **Step 2: Wire AffinityTracker into CafeRunner**

Read `cafe_runner.ex`. After `persist_cafe/6`, add a call to update bonds:

```elixir
      AffinityTracker.update_from_cafe(actor_ids)
```

Add the alias:
```elixir
  alias PopulationSimulator.Simulation.AffinityTracker
```

Also load bonds when building the prompt in `process_table/3`:

```elixir
    bonds = AffinityTracker.load_bonds_between(actor_ids)
    {prompt, names} = CafePromptBuilder.build(measure, table_actors, bonds)
```

- [ ] **Step 3: Verify compilation and tests**

Run: `mix compile && mix test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator/simulation/cafe_prompt_builder.ex lib/population_simulator/simulation/cafe_runner.ex
git commit -m "Annotate bonds in café prompts and wire AffinityTracker into CafeRunner"
```

---

## Task 5: CLAUDE.md docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add bonds documentation**

After the cognitive dissonance bullet in Key design decisions:

```markdown
- **Social bonds**: AffinityTracker tracks emergent relationships between actors. Pairs who share 3+ cafés form bonds (max 10 per actor). CafeGrouper prefers seating bonded actors together. CafePromptBuilder annotates bonds so the LLM generates dialogue with social history. Affinity decays -0.1 per measure without shared café; bonds deleted at 0.
```

In Core Modules table:
```markdown
| `AffinityTracker` | Emergent social bonds: formation, decay, bond-aware queries |
```

In Database Schema:
```markdown
- **actor_bonds** — emergent social relationships with affinity, shared café count, formation date
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document emergent social bonds in CLAUDE.md"
```
