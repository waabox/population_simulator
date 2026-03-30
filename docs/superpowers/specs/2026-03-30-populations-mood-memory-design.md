# Populations, Mood & Actor Memory

## Context

The population simulator currently evaluates each actor's reaction to a measure in isolation — no memory of past measures, no accumulated emotional state. This design adds:

1. **Populations** — named groups of actors that remain fixed across simulation rounds
2. **Actor Mood** — 5 quantifiable dimensions that evolve with each measure
3. **Actor Memory** — structured history of past decisions + LLM-generated narrative carried forward as context

The goal is to observe how actors shift opinions over time as their mood mutates based on whether measures benefit or harm them.

## Data Model

### New Tables

#### `populations`

| Field       | Type         | Constraints          |
|-------------|--------------|----------------------|
| id          | UUID         | PK                   |
| name        | string       | unique, not null     |
| description | text         | nullable             |
| timestamps  | utc_datetime |                      |

#### `actor_populations`

| Field         | Type         | Constraints                    |
|---------------|--------------|--------------------------------|
| id            | UUID         | PK                             |
| actor_id      | UUID         | FK -> actors, not null         |
| population_id | UUID         | FK -> populations, not null    |
| timestamps    | utc_datetime |                                |
| unique index  |              | (actor_id, population_id)      |

#### `actor_moods`

| Field                | Type         | Constraints                              |
|----------------------|--------------|------------------------------------------|
| id                   | UUID         | PK                                       |
| actor_id             | UUID         | FK -> actors, not null                    |
| decision_id          | UUID         | FK -> decisions, nullable (null = initial)|
| measure_id           | UUID         | FK -> measures, nullable (null = initial) |
| economic_confidence  | integer      | 1-10, not null                           |
| government_trust     | integer      | 1-10, not null                           |
| personal_wellbeing   | integer      | 1-10, not null                           |
| social_anger         | integer      | 1-10, not null                           |
| future_outlook       | integer      | 1-10, not null                           |
| narrative            | text         | LLM-generated emotional summary          |
| timestamps           | utc_datetime |                                          |
| index                |              | (actor_id, inserted_at)                  |

### Changes to Existing Tables

- **`measures`**: add optional `population_id` (FK -> populations, nullable). Null means the measure applies to all actors.

## Mood Dimensions

All dimensions are integers on a 1-10 scale:

| Dimension              | Description                                         |
|------------------------|-----------------------------------------------------|
| `economic_confidence`  | How well the actor expects to do economically        |
| `government_trust`     | Trust in the current government                      |
| `personal_wellbeing`   | Perceived personal/family wellbeing                  |
| `social_anger`         | Level of social frustration/anger                    |
| `future_outlook`       | Optimism vs pessimism about the future               |

## Initial Mood

When actors are seeded, an initial `actor_mood` record is created (no `decision_id` or `measure_id`) with values derived from the actor's profile:

- `government_trust` <- from profile's existing `government_trust` field
- `economic_confidence` <- derived from stratum + employment type
- `personal_wellbeing` <- derived from income vs CBT ratio
- `social_anger` <- inverse of government_trust + stratum adjustment
- `future_outlook` <- derived from inflation_expectation + age

## Simulation Flow

### Current Flow

```
Actor + Measure -> PromptBuilder -> LLM -> Decision -> DB
```

### New Flow

```
Actor + Measure + Last Mood + History -> PromptBuilder -> LLM -> Decision + New Mood -> DB (transaction)
```

### Step by Step

1. `MeasureRunner.run/2` receives `measure_id` and options (now includes optional `population_id`)
2. If `population_id` is present, filter actors via `actor_populations` join. Otherwise, fetch all actors.
3. For each actor, preload the latest `actor_mood` (ORDER BY inserted_at DESC LIMIT 1)
4. `PromptBuilder.build/3` now receives `(profile, measure, current_mood)`:
   - Includes the 5 numeric mood dimensions
   - Includes the narrative from the last N mood entries (e.g., last 3)
   - Includes a summary of recent decisions (measure title + agreement + intensity)
5. The LLM prompt requests an extended JSON response:
   - Existing: `agreement`, `intensity`, `reasoning`, `personal_impact`, `behavior_change`
   - New: `mood_update` object with the 5 updated dimensions (1-10) and a `narrative` (short text)
6. Persisted in a single transaction:
   - The `Decision` record (as today)
   - A new `ActorMood` record linked to that decision and measure

### Prompt Structure

The prompt includes a new memory/mood section:

```
=== YOUR RECENT HISTORY ===
- Measure "Aumento de retenciones al campo": Disagreed (intensity 8/10)
- Measure "Bono de $50.000 a jubilados": Agreed (intensity 6/10)

=== YOUR CURRENT EMOTIONAL STATE ===
Economic confidence: 4/10 | Government trust: 3/10
Personal wellbeing: 5/10 | Social anger: 7/10 | Future outlook: 3/10

"Estoy cada vez mas frustrado. Las medidas no me benefician y siento que
el gobierno no entiende mi situacion."

=== NEW MEASURE ===
...
```

Note: prompts remain in Spanish (actors are Argentine citizens).

## CLI Commands

### Population Management

```bash
# Create a population
mix sim.population.create --name "Base Argentina" --description "General GBA population"

# List populations
mix sim.population.list

# Assign actors to a population (all or filtered, with optional limit)
mix sim.population.assign --name "Base Argentina"
mix sim.population.assign --name "Young CABA" --zone caba_north,caba_south --age-max 35 --limit 100

# Show population composition
mix sim.population.info --name "Base Argentina"
```

### Simulation Changes

```bash
# Run a measure on a specific population (always the same fixed actors)
mix sim.run --title "..." --description "..." --population "Base Argentina"

# Run a measure on all actors (unchanged)
mix sim.run --title "..." --description "..."
```

### Seeding Changes

```bash
# Seed actors and optionally assign to a population
mix sim.seed --n 5000 --population "Base Argentina"

# Seed without population (as today)
mix sim.seed --n 5000
```

`sim.seed` now also creates the initial mood for each actor.

### Mood Queries

```bash
# Current average mood for a population
mix sim.mood --population "Base Argentina"

# Mood evolution across measures
mix sim.mood --population "Base Argentina" --history
```

## Metrics & Aggregation

### New Mood Metrics

- Average current mood (5 dimensions) for a population
- Mood evolution over time (delta per dimension per measure)
- Mood distribution by stratum/zone within a population

### Opinion Shift Detection

- Actors who flipped `agreement` between consecutive measures
- Average delta per mood dimension between rounds
- Most volatile actors (highest cumulative mood delta)

### Output Format

```
=== Population: Panel Fijo (100 actors) ===

Current Mood Averages:
  Economic confidence:  4.2/10
  Government trust:     3.8/10
  Personal wellbeing:   5.1/10
  Social anger:         6.4/10
  Future outlook:       3.9/10

Evolution (last 3 measures):
  Measure                          | Econ | Trust | Well | Anger | Future
  "Aumento retenciones"            | -0.8 | -1.2  | -0.3 | +1.5  | -0.9
  "Bono jubilados"                 | +0.2 | +0.5  | +0.4 | -0.3  | +0.3
  "Cepo al dolar"                  | -1.1 | -0.8  | -0.7 | +1.8  | -1.2

Opinion shifts: 12 actors flipped agreement on last measure
Most volatile: 8 actors with cumulative mood delta > 15
```

## New Files

- `lib/population_simulator/populations/population.ex` — Ecto schema
- `lib/population_simulator/populations/actor_population.ex` — Ecto schema
- `lib/population_simulator/simulation/actor_mood.ex` — Ecto schema
- `lib/mix/tasks/sim.population.create.ex` — Mix task
- `lib/mix/tasks/sim.population.list.ex` — Mix task
- `lib/mix/tasks/sim.population.assign.ex` — Mix task
- `lib/mix/tasks/sim.population.info.ex` — Mix task
- `lib/mix/tasks/sim.mood.ex` — Mix task
- 3 migrations: create_populations, create_actor_populations, create_actor_moods

## Modified Files

- `prompt_builder.ex` — add mood + history to prompt
- `measure_runner.ex` — filter by population, load mood, persist mood post-decision
- `aggregator.ex` — mood metrics and evolution
- `sim.seed.ex` — create initial mood, `--population` option
- `sim.run.ex` — `--population` option
- `measure.ex` — add optional `population_id`
