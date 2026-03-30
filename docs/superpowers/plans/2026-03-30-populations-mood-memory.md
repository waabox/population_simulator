# Populations, Mood & Actor Memory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add named populations, per-actor mood dimensions that evolve with each measure, and actor memory (structured history + LLM narrative) to the population simulator.

**Architecture:** Three new DB tables (populations, actor_populations, actor_moods) with Ecto schemas. MeasureRunner gains population filtering and mood persistence. PromptBuilder includes mood history in prompts. LLM response is extended with mood_update. New Mix tasks for population and mood management.

**Tech Stack:** Elixir/Ecto/SQLite3, existing project patterns (UUID PKs, raw SQL for aggregation, Task.async_stream for concurrency).

---

### Task 1: Migration — Create populations table

**Files:**
- Create: `priv/repo/migrations/20260330100000_create_populations.exs`

- [ ] **Step 1: Create the migration**

```elixir
defmodule PopulationSimulator.Repo.Migrations.CreatePopulations do
  use Ecto.Migration

  def change do
    create table(:populations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:populations, [:name])
  end
end
```

- [ ] **Step 2: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully, table created.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations/20260330100000_create_populations.exs
git commit -m "Add populations migration"
```

---

### Task 2: Migration — Create actor_populations table

**Files:**
- Create: `priv/repo/migrations/20260330100001_create_actor_populations.exs`

- [ ] **Step 1: Create the migration**

```elixir
defmodule PopulationSimulator.Repo.Migrations.CreateActorPopulations do
  use Ecto.Migration

  def change do
    create table(:actor_populations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :uuid, on_delete: :delete_all), null: false
      add :population_id, references(:populations, type: :uuid, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:actor_populations, [:actor_id, :population_id])
    create index(:actor_populations, [:population_id])
  end
end
```

- [ ] **Step 2: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations/20260330100001_create_actor_populations.exs
git commit -m "Add actor_populations migration"
```

---

### Task 3: Migration — Create actor_moods table

**Files:**
- Create: `priv/repo/migrations/20260330100002_create_actor_moods.exs`

- [ ] **Step 1: Create the migration**

```elixir
defmodule PopulationSimulator.Repo.Migrations.CreateActorMoods do
  use Ecto.Migration

  def change do
    create table(:actor_moods, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :uuid, on_delete: :delete_all), null: false
      add :decision_id, references(:decisions, type: :uuid, on_delete: :nilify_all)
      add :measure_id, references(:measures, type: :uuid, on_delete: :nilify_all)
      add :economic_confidence, :integer, null: false
      add :government_trust, :integer, null: false
      add :personal_wellbeing, :integer, null: false
      add :social_anger, :integer, null: false
      add :future_outlook, :integer, null: false
      add :narrative, :text
      timestamps(type: :utc_datetime)
    end

    create index(:actor_moods, [:actor_id, :inserted_at])
    create index(:actor_moods, [:decision_id])
  end
end
```

- [ ] **Step 2: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations/20260330100002_create_actor_moods.exs
git commit -m "Add actor_moods migration"
```

---

### Task 4: Migration — Add population_id to measures

**Files:**
- Create: `priv/repo/migrations/20260330100003_add_population_id_to_measures.exs`

- [ ] **Step 1: Create the migration**

```elixir
defmodule PopulationSimulator.Repo.Migrations.AddPopulationIdToMeasures do
  use Ecto.Migration

  def change do
    alter table(:measures) do
      add :population_id, references(:populations, type: :uuid, on_delete: :nilify_all)
    end

    create index(:measures, [:population_id])
  end
end
```

- [ ] **Step 2: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations/20260330100003_add_population_id_to_measures.exs
git commit -m "Add population_id to measures"
```

---

### Task 5: Ecto Schema — Population

**Files:**
- Create: `lib/population_simulator/populations/population.ex`

- [ ] **Step 1: Create the Population schema**

```elixir
defmodule PopulationSimulator.Populations.Population do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "populations" do
    field :name, :string
    field :description, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(population, attrs) do
    population
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/populations/population.ex
git commit -m "Add Population Ecto schema"
```

---

### Task 6: Ecto Schema — ActorPopulation

**Files:**
- Create: `lib/population_simulator/populations/actor_population.ex`

- [ ] **Step 1: Create the ActorPopulation schema**

```elixir
defmodule PopulationSimulator.Populations.ActorPopulation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actor_populations" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :population, PopulationSimulator.Populations.Population, type: :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(actor_population, attrs) do
    actor_population
    |> cast(attrs, [:actor_id, :population_id])
    |> validate_required([:actor_id, :population_id])
    |> unique_constraint([:actor_id, :population_id])
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/populations/actor_population.ex
git commit -m "Add ActorPopulation Ecto schema"
```

---

### Task 7: Ecto Schema — ActorMood

**Files:**
- Create: `lib/population_simulator/simulation/actor_mood.ex`

- [ ] **Step 1: Create the ActorMood schema**

```elixir
defmodule PopulationSimulator.Simulation.ActorMood do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actor_moods" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :decision, PopulationSimulator.Simulation.Decision, type: :binary_id
    belongs_to :measure, PopulationSimulator.Simulation.Measure, type: :binary_id
    field :economic_confidence, :integer
    field :government_trust, :integer
    field :personal_wellbeing, :integer
    field :social_anger, :integer
    field :future_outlook, :integer
    field :narrative, :string
    timestamps(type: :utc_datetime)
  end

  @mood_fields [:economic_confidence, :government_trust, :personal_wellbeing, :social_anger, :future_outlook, :narrative]

  def changeset(mood, attrs) do
    mood
    |> cast(attrs, [:actor_id, :decision_id, :measure_id | @mood_fields])
    |> validate_required([:actor_id, :economic_confidence, :government_trust, :personal_wellbeing, :social_anger, :future_outlook])
    |> validate_number(:economic_confidence, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:government_trust, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:personal_wellbeing, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:social_anger, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:future_outlook, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
  end

  def initial_from_profile(actor_id, profile) do
    government_trust = profile_trust_to_mood(profile["government_trust"])
    economic_confidence = derive_economic_confidence(profile)
    personal_wellbeing = derive_personal_wellbeing(profile)
    social_anger = derive_social_anger(government_trust, profile)
    future_outlook = derive_future_outlook(profile)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: nil,
      measure_id: nil,
      economic_confidence: economic_confidence,
      government_trust: government_trust,
      personal_wellbeing: personal_wellbeing,
      social_anger: social_anger,
      future_outlook: future_outlook,
      narrative: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  def from_llm_response(actor_id, decision_id, measure_id, mood_update) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: decision_id,
      measure_id: measure_id,
      economic_confidence: clamp(mood_update["economic_confidence"], 1, 10),
      government_trust: clamp(mood_update["government_trust"], 1, 10),
      personal_wellbeing: clamp(mood_update["personal_wellbeing"], 1, 10),
      social_anger: clamp(mood_update["social_anger"], 1, 10),
      future_outlook: clamp(mood_update["future_outlook"], 1, 10),
      narrative: mood_update["narrative"],
      inserted_at: now,
      updated_at: now
    }
  end

  # government_trust in profile is 1.0-5.0 float, convert to 1-10 integer
  defp profile_trust_to_mood(trust) when is_number(trust) do
    round(trust * 2) |> clamp(1, 10)
  end
  defp profile_trust_to_mood(_), do: 5

  defp derive_economic_confidence(profile) do
    base = case profile["stratum"] do
      "upper" -> 8
      "upper_middle" -> 7
      "middle" -> 5
      "lower_middle" -> 4
      "low" -> 3
      "destitute" -> 2
      _ -> 5
    end

    employment_adj = case profile["employment_type"] do
      "formal_employee" -> 1
      "employer" -> 1
      "unemployed" -> -2
      "informal_employee" -> -1
      _ -> 0
    end

    clamp(base + employment_adj, 1, 10)
  end

  defp derive_personal_wellbeing(profile) do
    income = profile["income"] || 0
    basket = profile["basic_basket"] || 1

    ratio = income / max(basket, 1)

    cond do
      ratio >= 3.0 -> 8
      ratio >= 2.0 -> 7
      ratio >= 1.5 -> 6
      ratio >= 1.0 -> 5
      ratio >= 0.7 -> 3
      true -> 2
    end
  end

  defp derive_social_anger(government_trust, profile) do
    base = 11 - government_trust  # inverse of trust

    stratum_adj = case profile["stratum"] do
      "destitute" -> 1
      "low" -> 1
      "upper" -> -1
      _ -> 0
    end

    clamp(base + stratum_adj, 1, 10)
  end

  defp derive_future_outlook(profile) do
    base = case profile["inflation_expectation"] do
      "very_pessimistic" -> 2
      "pessimistic" -> 4
      "neutral" -> 5
      "optimistic" -> 7
      _ -> 5
    end

    age_adj = cond do
      (profile["age"] || 30) < 30 -> 1
      (profile["age"] || 30) > 60 -> -1
      true -> 0
    end

    clamp(base + age_adj, 1, 10)
  end

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, min_v, _), do: min_v
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/actor_mood.ex
git commit -m "Add ActorMood Ecto schema with derivation logic"
```

---

### Task 8: Update Measure schema — add population_id

**Files:**
- Modify: `lib/population_simulator/simulation/measure.ex`

- [ ] **Step 1: Add the population_id field and update changeset**

In `lib/population_simulator/simulation/measure.ex`, update the schema and changeset:

```elixir
defmodule PopulationSimulator.Simulation.Measure do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "measures" do
    field :title, :string
    field :description, :string
    field :category, :string
    field :tags, :string
    belongs_to :population, PopulationSimulator.Populations.Population, type: :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(measure, attrs) do
    measure
    |> cast(attrs, [:title, :description, :category, :tags, :population_id])
    |> validate_required([:title, :description])
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/measure.ex
git commit -m "Add population_id to Measure schema"
```

---

### Task 9: Mix Task — sim.population.create

**Files:**
- Create: `lib/mix/tasks/sim.population.create.ex`

- [ ] **Step 1: Create the task**

```elixir
defmodule Mix.Tasks.Sim.Population.Create do
  use Mix.Task

  @shortdoc "Creates a named population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [name: :string, description: :string]
      )

    name = opts[:name] || raise "Required: --name"
    description = opts[:description]

    alias PopulationSimulator.Populations.Population

    case PopulationSimulator.Repo.insert(
           Population.changeset(%Population{}, %{name: name, description: description})
         ) do
      {:ok, population} ->
        IO.puts("Population created: #{population.name} (#{population.id})")

      {:error, changeset} ->
        IO.puts("Error: #{inspect(changeset.errors)}")
    end
  end
end
```

- [ ] **Step 2: Test manually**

Run: `mix sim.population.create --name "Test Population" --description "A test"`
Expected: `Population created: Test Population (<uuid>)`

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.population.create.ex
git commit -m "Add sim.population.create mix task"
```

---

### Task 10: Mix Task — sim.population.list

**Files:**
- Create: `lib/mix/tasks/sim.population.list.ex`

- [ ] **Step 1: Create the task**

```elixir
defmodule Mix.Tasks.Sim.Population.List do
  use Mix.Task

  @shortdoc "Lists all populations with actor counts"

  def run(_args) do
    Mix.Task.run("app.start")

    alias PopulationSimulator.Repo

    %{rows: rows} =
      Repo.query!("""
      SELECT p.id, p.name, p.description, COUNT(ap.id) as actor_count, p.inserted_at
      FROM populations p
      LEFT JOIN actor_populations ap ON ap.population_id = p.id
      GROUP BY p.id, p.name, p.description, p.inserted_at
      ORDER BY p.inserted_at DESC
      """)

    if rows == [] do
      IO.puts("No populations found.")
    else
      IO.puts("\n--- Populations ---")

      Enum.each(rows, fn [id, name, description, count, inserted_at] ->
        desc = if description, do: " — #{description}", else: ""
        IO.puts("  #{name} (#{count} actors)#{desc}")
        IO.puts("    ID: #{id} | Created: #{inserted_at}")
      end)

      IO.puts("")
    end
  end
end
```

- [ ] **Step 2: Test manually**

Run: `mix sim.population.list`
Expected: Shows the population created in Task 9.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.population.list.ex
git commit -m "Add sim.population.list mix task"
```

---

### Task 11: Mix Task — sim.population.assign

**Files:**
- Create: `lib/mix/tasks/sim.population.assign.ex`

- [ ] **Step 1: Create the task**

```elixir
defmodule Mix.Tasks.Sim.Population.Assign do
  use Mix.Task

  @shortdoc "Assigns actors to a population (with optional filters)"

  import Ecto.Query

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          name: :string,
          limit: :integer,
          zone: :string,
          stratum: :string,
          employment_type: :string,
          age_min: :integer,
          age_max: :integer
        ]
      )

    name = opts[:name] || raise "Required: --name"

    alias PopulationSimulator.{Repo, Actors.Actor, Populations.Population}

    population =
      Repo.get_by!(Population, name: name)

    query = from(a in Actor, select: a.id)
    query = apply_filters(query, opts)
    query = if opts[:limit], do: from(q in query, order_by: fragment("RANDOM()"), limit: ^opts[:limit]), else: query

    actor_ids = Repo.all(query)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(actor_ids, fn actor_id ->
        %{
          id: Ecto.UUID.generate(),
          actor_id: actor_id,
          population_id: population.id,
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(PopulationSimulator.Populations.ActorPopulation, chunk,
        on_conflict: :nothing,
        conflict_target: [:actor_id, :population_id]
      )
    end)

    IO.puts("Assigned #{length(actor_ids)} actors to population '#{name}'")
  end

  defp apply_filters(query, opts) do
    query
    |> filter_zone(opts[:zone])
    |> filter_stratum(opts[:stratum])
    |> filter_employment(opts[:employment_type])
    |> filter_age_min(opts[:age_min])
    |> filter_age_max(opts[:age_max])
  end

  defp filter_zone(query, nil), do: query
  defp filter_zone(query, zones) do
    zone_list = String.split(zones, ",")
    from(a in query, where: a.zone in ^zone_list)
  end

  defp filter_stratum(query, nil), do: query
  defp filter_stratum(query, strata) do
    stratum_list = String.split(strata, ",")
    from(a in query, where: a.stratum in ^stratum_list)
  end

  defp filter_employment(query, nil), do: query
  defp filter_employment(query, types) do
    type_list = String.split(types, ",")
    from(a in query, where: a.employment_type in ^type_list)
  end

  defp filter_age_min(query, nil), do: query
  defp filter_age_min(query, min), do: from(a in query, where: a.age >= ^min)

  defp filter_age_max(query, nil), do: query
  defp filter_age_max(query, max), do: from(a in query, where: a.age <= ^max)
end
```

- [ ] **Step 2: Test manually**

Run: `mix sim.population.assign --name "Test Population" --limit 10`
Expected: `Assigned 10 actors to population 'Test Population'`

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.population.assign.ex
git commit -m "Add sim.population.assign mix task with filters"
```

---

### Task 12: Mix Task — sim.population.info

**Files:**
- Create: `lib/mix/tasks/sim.population.info.ex`

- [ ] **Step 1: Create the task**

```elixir
defmodule Mix.Tasks.Sim.Population.Info do
  use Mix.Task

  @shortdoc "Shows composition of a population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [name: :string]
      )

    name = opts[:name] || raise "Required: --name"

    alias PopulationSimulator.Repo

    population = Repo.get_by!(PopulationSimulator.Populations.Population, name: name)

    IO.puts("\n=== Population: #{population.name} ===")
    if population.description, do: IO.puts("Description: #{population.description}")

    base_query = """
    SELECT a.{dim}, COUNT(*) as n
    FROM actors a
    JOIN actor_populations ap ON ap.actor_id = a.id
    WHERE ap.population_id = ?1
    GROUP BY 1
    ORDER BY 2 DESC
    """

    print_breakdown(Repo, "Stratum", base_query, "stratum", population.id)
    print_breakdown(Repo, "Zone", base_query, "zone", population.id)
    print_breakdown(Repo, "Employment", base_query, "employment_type", population.id)

    %{rows: [[count]]} =
      Repo.query!(
        "SELECT COUNT(*) FROM actor_populations WHERE population_id = ?1",
        [population.id]
      )

    IO.puts("\nTotal actors: #{count}\n")
  end

  defp print_breakdown(repo, label, query_template, dimension, population_id) do
    query = String.replace(query_template, "{dim}", dimension)
    %{rows: rows} = repo.query!(query, [population_id])

    IO.puts("\n--- #{label} ---")
    total = Enum.reduce(rows, 0, fn [_, n], acc -> acc + n end)

    Enum.each(rows, fn [value, n] ->
      pct = Float.round(n / max(total, 1) * 100, 1)
      IO.puts("  #{value}: #{n} (#{pct}%)")
    end)
  end
end
```

- [ ] **Step 2: Test manually**

Run: `mix sim.population.info --name "Test Population"`
Expected: Shows breakdown by stratum, zone, employment for the population.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.population.info.ex
git commit -m "Add sim.population.info mix task"
```

---

### Task 13: Update sim.seed — Create initial moods and optional population assignment

**Files:**
- Modify: `lib/mix/tasks/sim.seed.ex`
- Modify: `lib/population_simulator/actors/actor.ex`

- [ ] **Step 1: Update Actor.insert_all to return inserted IDs**

In `lib/population_simulator/actors/actor.ex`, replace the `insert_all/1` function:

```elixir
  def insert_all(actors) do
    rows = Enum.map(actors, &from_enriched/1)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      PopulationSimulator.Repo.insert_all(__MODULE__, chunk,
        on_conflict: :nothing,
        conflict_target: [:id]
      )
    end)

    rows
  end
```

Note: the function now returns the inserted row maps (which contain the `id` and `profile` fields needed for initial mood creation).

- [ ] **Step 2: Update sim.seed to create initial moods and assign populations**

Replace the full content of `lib/mix/tasks/sim.seed.ex`:

```elixir
defmodule Mix.Tasks.Sim.Seed do
  use Mix.Task

  @shortdoc "Seeds population from INDEC EPH files"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [n: :integer, individual: :string, hogar: :string, population: :string]
      )

    n = opts[:n] || 5_000
    individual = opts[:individual] || "priv/data/eph/individual.txt"
    hogar = opts[:hogar] || "priv/data/eph/hogar.txt"
    population_name = opts[:population]

    IO.puts("Loading EPH GBA...")
    individuos = PopulationSimulator.DataPipeline.EphLoader.load(individual, hogar)
    IO.puts("#{length(individuos)} individuals found in EPH sample")

    IO.puts("Sampling #{n} weighted actors...")
    sample = PopulationSimulator.DataPipeline.PopulationSampler.sample(n, individuos)

    IO.puts("Enriching with synthetic variables...")
    actores = Enum.map(sample, &PopulationSimulator.DataPipeline.ActorEnricher.enrich/1)

    IO.puts("Persisting to DB...")
    rows = PopulationSimulator.Actors.Actor.insert_all(actores)

    IO.puts("Creating initial moods...")
    create_initial_moods(rows)

    if population_name do
      assign_to_population(rows, population_name)
    end

    IO.puts("Population of #{n} actors created from real EPH GBA data")

    print_distribution("Stratum", actores, :stratum)
    print_distribution("Zone", actores, :zone)
    print_distribution("Employment", actores, :employment_type)
  end

  defp create_initial_moods(rows) do
    alias PopulationSimulator.{Repo, Simulation.ActorMood}

    rows
    |> Enum.map(fn row -> ActorMood.initial_from_profile(row.id, row.profile) end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(ActorMood, chunk, on_conflict: :nothing)
    end)
  end

  defp assign_to_population(rows, population_name) do
    alias PopulationSimulator.{Repo, Populations.Population, Populations.ActorPopulation}

    population =
      case Repo.get_by(Population, name: population_name) do
        nil ->
          {:ok, p} = Repo.insert(Population.changeset(%Population{}, %{name: population_name}))
          IO.puts("Population '#{population_name}' created.")
          p

        existing ->
          existing
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows
    |> Enum.map(fn row ->
      %{
        id: Ecto.UUID.generate(),
        actor_id: row.id,
        population_id: population.id,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(ActorPopulation, chunk, on_conflict: :nothing, conflict_target: [:actor_id, :population_id])
    end)

    IO.puts("Assigned #{length(rows)} actors to population '#{population_name}'")
  end

  defp print_distribution(label, actores, key) do
    dist =
      actores
      |> Enum.group_by(&Map.get(&1, key))
      |> Enum.map(fn {k, v} -> {k, length(v)} end)
      |> Enum.sort_by(fn {_, count} -> -count end)

    IO.puts("\n--- #{label} ---")

    Enum.each(dist, fn {k, count} ->
      pct = Float.round(count / length(actores) * 100, 1)
      IO.puts("  #{k}: #{count} (#{pct}%)")
    end)
  end
end
```

- [ ] **Step 3: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 4: Commit**

```bash
git add lib/mix/tasks/sim.seed.ex lib/population_simulator/actors/actor.ex
git commit -m "Update sim.seed to create initial moods and assign populations"
```

---

### Task 14: Update PromptBuilder — Add mood and history context

**Files:**
- Modify: `lib/population_simulator/simulation/prompt_builder.ex`

- [ ] **Step 1: Add the build/3 function and mood helpers**

Add the following functions to `lib/population_simulator/simulation/prompt_builder.ex`. Keep the existing `build/2` function intact, and add `build/3` below it:

```elixir
  def build(profile, measure, mood_context) when is_map(profile) do
    """
    #{base(profile)}

    #{mood_section(mood_context)}

    ---

    El gobierno nacional anunció la siguiente medida económica:

    "#{measure.description}"

    Respondé ÚNICAMENTE con JSON válido. Sin texto antes ni después. Sin markdown.

    {
      "agreement": true | false (si estás de acuerdo o no),
      "intensity": <número entero del 1 al 10, donde 1=totalmente en contra y 10=totalmente a favor>,
      "reasoning": "<explicación en primera persona desde tu perfil, máximo 2 oraciones>",
      "personal_impact": "<cómo te afecta esta medida específicamente>",
      "behavior_change": "<qué harías diferente, si algo, ante esta medida>",
      "mood_update": {
        "economic_confidence": <1-10>,
        "government_trust": <1-10>,
        "personal_wellbeing": <1-10>,
        "social_anger": <1-10>,
        "future_outlook": <1-10>,
        "narrative": "<cómo te sentís ahora en general, máximo 2 oraciones>"
      }
    }
    """
  end

  defp mood_section(%{current_mood: current_mood, history: history}) do
    history_text = format_history(history)

    """
    === TU HISTORIAL RECIENTE ===
    #{history_text}

    === TU ESTADO EMOCIONAL ACTUAL ===
    Confianza económica: #{current_mood.economic_confidence}/10 | Confianza en el gobierno: #{current_mood.government_trust}/10
    Bienestar personal: #{current_mood.personal_wellbeing}/10 | Bronca social: #{current_mood.social_anger}/10 | Expectativa futura: #{current_mood.future_outlook}/10
    #{narrative_text(current_mood.narrative)}
    """
  end

  defp format_history([]), do: "Sin historial previo — esta es tu primera medida."

  defp format_history(history) do
    history
    |> Enum.map(fn entry ->
      agreement_text = if entry.agreement, do: "De acuerdo", else: "En desacuerdo"
      "- Medida \"#{entry.measure_title}\": #{agreement_text} (intensidad #{entry.intensity}/10)"
    end)
    |> Enum.join("\n")
  end

  defp narrative_text(nil), do: ""
  defp narrative_text(""), do: ""
  defp narrative_text(narrative), do: "\n\"#{narrative}\""
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/prompt_builder.ex
git commit -m "Add mood and history context to PromptBuilder"
```

---

### Task 15: Update ClaudeClient — Parse mood_update from response

**Files:**
- Modify: `lib/population_simulator/llm/claude_client.ex`

- [ ] **Step 1: Update parse_response to include mood_update**

In `lib/population_simulator/llm/claude_client.ex`, replace the `parse_response/1` function that handles the successful case:

```elixir
  defp parse_response(%{"content" => [%{"text" => text} | _], "usage" => usage}) do
    text_clean = text |> String.trim() |> strip_markdown()

    case Jason.decode(text_clean) do
      {:ok, parsed} ->
        decision = %{
          agreement: parsed["agreement"],
          intensity: parsed["intensity"],
          reasoning: parsed["reasoning"],
          personal_impact: parsed["personal_impact"],
          behavior_change: parsed["behavior_change"],
          tokens_used: usage["input_tokens"] + usage["output_tokens"],
          raw_response: parsed,
          mood_update: parsed["mood_update"]
        }

        {:ok, decision}

      {:error, _} ->
        {:error, "JSON parse error: #{text}"}
    end
  end
```

The only change is adding `mood_update: parsed["mood_update"]` to the decision map. When `build/2` is used (without mood), `parsed["mood_update"]` will be nil and MeasureRunner can skip mood persistence.

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/llm/claude_client.ex
git commit -m "Parse mood_update from LLM response in ClaudeClient"
```

---

### Task 16: Update MeasureRunner — Population filtering, mood loading, mood persistence

**Files:**
- Modify: `lib/population_simulator/simulation/measure_runner.ex`

- [ ] **Step 1: Rewrite MeasureRunner with population and mood support**

Replace the full content of `lib/population_simulator/simulation/measure_runner.ex`:

```elixir
defmodule PopulationSimulator.Simulation.MeasureRunner do
  @moduledoc """
  Orchestrates running an economic measure against actors.
  Supports population filtering, mood loading, and mood persistence.
  """

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.Decision,
                              Simulation.ActorMood}
  import Ecto.Query

  def run(measure_id, opts \\ []) do
    concurrency =
      Keyword.get(
        opts,
        :concurrency,
        Application.get_env(:population_simulator, :llm_concurrency, 30)
      )

    limit = Keyword.get(opts, :limit, nil)
    population_id = Keyword.get(opts, :population_id, nil)

    measure = Repo.get!(PopulationSimulator.Simulation.Measure, measure_id)

    actors = load_actors(population_id, limit)
    total = length(actors)

    IO.puts("Simulation started: #{total} actors, concurrency: #{concurrency}")
    start = System.monotonic_time(:second)

    results =
      actors
      |> Task.async_stream(
        fn actor -> evaluate_actor(actor, measure, measure_id) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0, tokens: 0, errors: []}, fn
        {:ok, {:ok, _, tokens}}, acc ->
          %{acc | ok: acc.ok + 1, tokens: acc.tokens + (tokens || 0)}

        {:ok, {:error, id, reason}}, acc ->
          %{acc | error: acc.error + 1, errors: [{id, reason} | acc.errors]}

        {:exit, _}, acc ->
          %{acc | error: acc.error + 1}
      end)

    elapsed = System.monotonic_time(:second) - start
    IO.puts("Completed in #{elapsed}s — OK: #{results.ok} | Errors: #{results.error} | Tokens: #{results.tokens}")

    {:ok, results}
  end

  defp load_actors(nil, limit) do
    query = from(a in Actor, select: a)
    query = if limit, do: from(q in query, limit: ^limit), else: query
    Repo.all(query)
  end

  defp load_actors(population_id, _limit) do
    Repo.all(
      from a in Actor,
        join: ap in "actor_populations",
        on: ap.actor_id == a.id,
        where: ap.population_id == ^population_id,
        select: a
    )
  end

  defp evaluate_actor(actor, measure, measure_id) do
    current_mood = load_latest_mood(actor.id)
    history = load_decision_history(actor.id, 3)

    prompt =
      if current_mood do
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(actor.profile, measure, mood_context)
      else
        PromptBuilder.build(actor.profile, measure)
      end

    case ClaudeClient.complete(prompt) do
      {:ok, decision} ->
        decision_row = Decision.from_llm_response(actor.id, measure_id, decision)

        Repo.insert_all(Decision, [decision_row],
          on_conflict: :nothing,
          conflict_target: [:actor_id, :measure_id]
        )

        if decision.mood_update do
          mood_row = ActorMood.from_llm_response(
            actor.id,
            decision_row.id,
            measure_id,
            decision.mood_update
          )

          Repo.insert_all(ActorMood, [mood_row], on_conflict: :nothing)
        end

        {:ok, actor.id, decision.tokens_used}

      {:error, reason} ->
        {:error, actor.id, reason}
    end
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

  defp load_decision_history(actor_id, n) do
    Repo.all(
      from d in "decisions",
        join: m in "measures",
        on: m.id == d.measure_id,
        where: d.actor_id == ^actor_id,
        order_by: [desc: d.inserted_at],
        limit: ^n,
        select: %{
          measure_title: m.title,
          agreement: d.agreement,
          intensity: d.intensity
        }
    )
    |> Enum.reverse()
    |> Enum.map(fn entry ->
      %{entry | agreement: entry.agreement == 1}
    end)
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/measure_runner.ex
git commit -m "Update MeasureRunner with population filtering and mood support"
```

---

### Task 17: Update sim.run — Add --population option

**Files:**
- Modify: `lib/mix/tasks/sim.run.ex`

- [ ] **Step 1: Update sim.run to accept --population**

Replace the full content of `lib/mix/tasks/sim.run.ex`:

```elixir
defmodule Mix.Tasks.Sim.Run do
  use Mix.Task

  @shortdoc "Runs an economic measure against the population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          title: :string,
          description: :string,
          concurrency: :integer,
          limit: :integer,
          population: :string
        ]
      )

    description = opts[:description] || raise "Required: --description"
    title = opts[:title] || "Medida"
    concurrency = opts[:concurrency] || 30
    limit = opts[:limit]
    population_name = opts[:population]

    population_id = resolve_population_id(population_name)

    measure_attrs = %{title: title, description: description}
    measure_attrs = if population_id, do: Map.put(measure_attrs, :population_id, population_id), else: measure_attrs

    {:ok, measure} =
      PopulationSimulator.Repo.insert(
        PopulationSimulator.Simulation.Measure.changeset(
          %PopulationSimulator.Simulation.Measure{},
          measure_attrs
        )
      )

    IO.puts("Measure: #{title}")
    if population_name, do: IO.puts("Population: #{population_name}")
    IO.puts("#{description}\n")

    run_opts = [concurrency: concurrency]
    run_opts = if population_id, do: Keyword.put(run_opts, :population_id, population_id), else: run_opts
    run_opts = if limit, do: Keyword.put(run_opts, :limit, limit), else: run_opts

    {:ok, results} = PopulationSimulator.Simulation.MeasureRunner.run(measure.id, run_opts)

    if results.ok > 0 do
      {:ok, metrics} = PopulationSimulator.Metrics.Aggregator.summary(measure.id)
      IO.inspect(metrics, label: "Metrics", pretty: true)
    end
  end

  defp resolve_population_id(nil), do: nil

  defp resolve_population_id(name) do
    alias PopulationSimulator.{Repo, Populations.Population}

    case Repo.get_by(Population, name: name) do
      nil -> raise "Population '#{name}' not found. Create it first with: mix sim.population.create --name \"#{name}\""
      population -> population.id
    end
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.run.ex
git commit -m "Add --population option to sim.run"
```

---

### Task 18: Update Aggregator — Add mood metrics

**Files:**
- Modify: `lib/population_simulator/metrics/aggregator.ex`

- [ ] **Step 1: Add mood_summary and mood_evolution functions**

Add the following functions to `lib/population_simulator/metrics/aggregator.ex`. Keep all existing functions, and add these at the bottom (before the `defp to_map` functions):

```elixir
  def mood_summary(population_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          ROUND(AVG(m.economic_confidence), 1) as economic_confidence,
          ROUND(AVG(m.government_trust), 1) as government_trust,
          ROUND(AVG(m.personal_wellbeing), 1) as personal_wellbeing,
          ROUND(AVG(m.social_anger), 1) as social_anger,
          ROUND(AVG(m.future_outlook), 1) as future_outlook,
          COUNT(*) as actor_count
        FROM actor_moods m
        JOIN (
          SELECT actor_id, MAX(inserted_at) as max_ts
          FROM actor_moods
          GROUP BY actor_id
        ) latest ON latest.actor_id = m.actor_id AND latest.max_ts = m.inserted_at
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        WHERE ap.population_id = ?1
        """,
        [population_id]
      )

    to_map(columns, List.first(rows))
  end

  def mood_evolution(population_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          ms.title as measure,
          ROUND(AVG(m.economic_confidence), 1) as economic_confidence,
          ROUND(AVG(m.government_trust), 1) as government_trust,
          ROUND(AVG(m.personal_wellbeing), 1) as personal_wellbeing,
          ROUND(AVG(m.social_anger), 1) as social_anger,
          ROUND(AVG(m.future_outlook), 1) as future_outlook
        FROM actor_moods m
        JOIN measures ms ON ms.id = m.measure_id
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        WHERE ap.population_id = ?1 AND m.measure_id IS NOT NULL
        GROUP BY m.measure_id, ms.title
        ORDER BY m.inserted_at
        """,
        [population_id]
      )

    Enum.map(rows, &to_map(columns, &1))
  end

  def opinion_shifts(population_id, measure_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT COUNT(*) FROM (
          SELECT d1.actor_id
          FROM decisions d1
          JOIN decisions d2 ON d2.actor_id = d1.actor_id
          JOIN actor_populations ap ON ap.actor_id = d1.actor_id
          WHERE ap.population_id = ?1
            AND d1.measure_id = ?2
            AND d2.measure_id != ?2
            AND d1.agreement != d2.agreement
            AND d2.inserted_at = (
              SELECT MAX(d3.inserted_at) FROM decisions d3
              WHERE d3.actor_id = d1.actor_id AND d3.measure_id != ?2
              AND d3.inserted_at < d1.inserted_at
            )
          GROUP BY d1.actor_id
        )
        """,
        [population_id, measure_id]
      )

    count
  end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/metrics/aggregator.ex
git commit -m "Add mood metrics to Aggregator"
```

---

### Task 19: Mix Task — sim.mood

**Files:**
- Create: `lib/mix/tasks/sim.mood.ex`

- [ ] **Step 1: Create the task**

```elixir
defmodule Mix.Tasks.Sim.Mood do
  use Mix.Task

  @shortdoc "Shows mood summary and evolution for a population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [population: :string, history: :boolean]
      )

    population_name = opts[:population] || raise "Required: --population"
    show_history = opts[:history] || false

    alias PopulationSimulator.{Repo, Populations.Population, Metrics.Aggregator}

    population = Repo.get_by!(Population, name: population_name)

    summary = Aggregator.mood_summary(population.id)

    IO.puts("\n=== Population: #{population.name} (#{summary["actor_count"]} actors) ===")
    IO.puts("")
    IO.puts("Current Mood Averages:")
    IO.puts("  Economic confidence:  #{summary["economic_confidence"]}/10")
    IO.puts("  Government trust:     #{summary["government_trust"]}/10")
    IO.puts("  Personal wellbeing:   #{summary["personal_wellbeing"]}/10")
    IO.puts("  Social anger:         #{summary["social_anger"]}/10")
    IO.puts("  Future outlook:       #{summary["future_outlook"]}/10")

    if show_history do
      evolution = Aggregator.mood_evolution(population.id)

      if evolution != [] do
        IO.puts("")
        IO.puts("Evolution by measure:")

        header = String.pad_trailing("Measure", 40) <>
          " | Econ | Trust | Well | Anger | Future"
        IO.puts("  #{header}")
        IO.puts("  #{String.duplicate("-", String.length(header))}")

        Enum.each(evolution, fn entry ->
          name = String.pad_trailing(String.slice(entry["measure"] || "", 0, 38), 40)

          IO.puts(
            "  #{name} | #{pad_num(entry["economic_confidence"])} | #{pad_num(entry["government_trust"])} | #{pad_num(entry["personal_wellbeing"])} | #{pad_num(entry["social_anger"])} | #{pad_num(entry["future_outlook"])}"
          )
        end)
      end
    end

    IO.puts("")
  end

  defp pad_num(nil), do: " -  "
  defp pad_num(n), do: String.pad_leading("#{n}", 4)
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.mood.ex
git commit -m "Add sim.mood mix task"
```

---

### Task 20: End-to-end manual verification

- [ ] **Step 1: Reset database and run full pipeline**

```bash
mix ecto.reset
```

- [ ] **Step 2: Seed actors with population**

```bash
mix sim.seed --n 100 --population "Test Panel"
```

Expected: Actors created, initial moods created, population assigned.

- [ ] **Step 3: Verify population was created**

```bash
mix sim.population.list
```

Expected: Shows "Test Panel" with 100 actors.

- [ ] **Step 4: View population info**

```bash
mix sim.population.info --name "Test Panel"
```

Expected: Shows stratum/zone/employment breakdown.

- [ ] **Step 5: Check initial moods**

```bash
mix sim.mood --population "Test Panel"
```

Expected: Shows average mood values derived from profiles.

- [ ] **Step 6: Run a measure against the population (requires CLAUDE_API_KEY)**

```bash
mix sim.run --title "Aumento de retenciones" --description "El gobierno aumenta las retenciones a la exportación de soja del 33% al 40%" --population "Test Panel" --limit 10
```

Expected: 10 actors evaluated, decisions + moods persisted.

- [ ] **Step 7: Check mood evolution**

```bash
mix sim.mood --population "Test Panel" --history
```

Expected: Shows current averages and evolution row for the measure.

- [ ] **Step 8: Run a second measure to verify mood carries over**

```bash
mix sim.run --title "Bono jubilados" --description "Se otorga un bono extraordinario de $70.000 a jubilados con haberes mínimos" --population "Test Panel" --limit 10
```

Expected: Same 10 actors, prompt now includes their history and mood from the first measure.

- [ ] **Step 9: Verify mood history shows both measures**

```bash
mix sim.mood --population "Test Panel" --history
```

Expected: Two rows in evolution table.

- [ ] **Step 10: Commit all work if any remaining changes**

```bash
git status
```

If clean, done. If any unstaged changes, commit them.
