# Population Simulator — Project Instructions

## Overview

Elixir/OTP application simulating GBA population reactions to economic measures.
Uses real INDEC EPH microdata + Claude API as the decision engine per actor.
Actors have persistent mood (5 dimensions), a belief graph (directed graph of causal/emotional relationships), and memory (decision history + narrative).

## Stack

- Elixir 1.19 / OTP 28
- SQLite3 (via ecto_sqlite3)
- Ecto for persistence
- Req for HTTP
- NimbleCSV for EPH parsing
- Claude API (Haiku) for actor decisions

## Architecture

### Data flow

```
INDEC EPH files → EphLoader → PopulationSampler → ActorEnricher → DB (actors)
Seed → ActorMood.initial_from_profile → DB (actor_moods)
Seed → BeliefGraph.from_template → DB (actor_beliefs)

Measure → MeasureRunner:
  For each actor:
    Load mood + beliefs + decision history
    → PromptBuilder (profile + mood + beliefs + history)
    → ClaudeClient
    → Decision + ActorMood + ActorBelief (all in transaction)

Aggregator → Metrics by stratum/zone/employment/orientation/mood/beliefs
```

### Key design decisions

- **Aglomerados**: GBA = CABA (32) + Partidos del GBA (33). Always filter both.
- **Income**: Uses P47T (total personal income) not TOT_P12. Falls back to per-capita household income (ITF / household_size) for zero-income members.
- **Scientific notation**: EPH uses `5e+05` format for large numbers. The `parse_number/1` function handles this.
- **Rent**: EPH no longer publishes rent amounts (II4_1 is categorical yes/no). Rent is estimated from housing type in CanastaFamiliar.
- **CBT**: `@cbt_adult_equivalent` in CanastaFamiliar must be updated monthly from INDEC.
- **Profiles are JSON**: Actor profiles are stored as JSON maps with string keys. PromptBuilder reads string keys, not atoms.
- **SQLite**: No Docker needed. DB file at project root (`population_simulator_dev.db`). SQLite doesn't support `FILTER (WHERE ...)` — use `CASE WHEN` instead. Booleans are stored as 0/1. Use `json_each()` and `json_extract()` for querying JSON fields.
- **Populations**: Named groups with fixed actor membership (many-to-many via actor_populations). When running a measure with `--population`, always the same actors respond.
- **Mood**: 5 dimensions (economic_confidence, government_trust, personal_wellbeing, social_anger, future_outlook), scale 1-10. Stored as snapshots in actor_moods. Initial mood derived from profile at seed time.
- **Belief graph**: Directed graph stored as JSON in actor_beliefs. Nodes are concepts (15 core + emergent). Edges are causal or emotional with weight -1.0 to 1.0. LLM returns deltas (modified/new/removed edges and new nodes), system applies them to produce full snapshot.
- **Belief templates**: 8 archetype templates in `priv/data/belief_templates/` (stratum x orientation). Generated via `mix sim.beliefs.init`. Applied with deterministic profile-based variations at seed time.
- **Prompt arities**: `PromptBuilder.build/2` (basic), `build/3` (with mood), `build/4` (with mood + beliefs). MeasureRunner selects the appropriate arity based on available data.

## Database Schema

### Tables

- **actors** — demographic profile, stratum, zone, age, employment, orientation
- **populations** — named groups (name unique)
- **actor_populations** — many-to-many (actor_id, population_id, unique index)
- **measures** — title, description, optional population_id
- **decisions** — actor reaction to a measure (agreement, intensity, reasoning, etc.)
- **actor_moods** — mood snapshot per actor per decision (5 dimensions + narrative)
- **actor_beliefs** — belief graph snapshot per actor per decision (JSON graph)

## Commands

```bash
# Database
mix ecto.create && mix ecto.migrate
mix ecto.reset                    # drop + create + migrate

# Data
./scripts/download_eph.sh 3 2025  # download EPH T3 2025

# Belief templates (requires API key, 8 LLM calls)
export CLAUDE_API_KEY=sk-ant-...
mix sim.beliefs.init

# Seed actors (creates moods + belief graphs + optional population)
mix sim.seed --n 5000
mix sim.seed --n 1000 --population "My Panel"

# Population management
mix sim.population.create --name "Panel A" --description "Test group"
mix sim.population.assign --name "Panel A" --limit 100 --zone caba_north
mix sim.population.list
mix sim.population.info --name "Panel A"

# Simulation
mix sim.run --title "Title" --description "Description" --population "My Panel"
mix sim.run --title "Title" --description "Description" --limit 100 --concurrency 30

# Mood queries
mix sim.mood --population "My Panel"
mix sim.mood --population "My Panel" --history

# Belief queries
mix sim.beliefs --population "My Panel"
mix sim.beliefs --population "My Panel" --emergent
mix sim.beliefs --population "My Panel" --edge "taxes->employment" --history

# Console
iex -S mix
```

## Conventions

- Module prefix: `PopulationSimulator`
- EPH data files go in `priv/data/eph/` (gitignored)
- Belief templates go in `priv/data/belief_templates/` (committed)
- Migrations in `priv/repo/migrations/`
- Mix tasks in `lib/mix/tasks/sim.*.ex`
- All prompts are in Spanish (actors are Argentine citizens)
- Metric keys are strings (from raw SQL queries)
- Belief graph nodes use snake_case English IDs
- Belief graph edges use (from, to, type) as composite key

## Core Modules

| Module | Responsibility |
|--------|---------------|
| `BeliefGraph` | Graph construction, delta application, template variations, humanization for prompts |
| `ActorMood` | Mood schema, initial derivation from profile, LLM response parsing |
| `ActorBelief` | Belief schema, initial/update factory functions |
| `PromptBuilder` | Builds prompts with profile + mood + beliefs + history (arities 2/3/4) |
| `MeasureRunner` | Orchestrates concurrent evaluation, loads mood/beliefs, persists all results |
| `Aggregator` | SQL metrics for decisions, mood evolution, belief summary, emergent nodes |

## Testing

No test suite yet. To verify the pipeline manually:

```elixir
# In iex -S mix
PopulationSimulator.Repo.aggregate(PopulationSimulator.Actors.Actor, :count)

# Check mood averages
Ecto.Adapters.SQL.query!(PopulationSimulator.Repo,
  "SELECT ROUND(AVG(economic_confidence),1), ROUND(AVG(social_anger),1) FROM actor_moods")

# Check belief graph edge count
Ecto.Adapters.SQL.query!(PopulationSimulator.Repo,
  "SELECT COUNT(*) FROM actor_beliefs")
```
