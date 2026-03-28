# Population Simulator — Project Instructions

## Overview

Elixir/OTP application simulating GBA population reactions to economic measures.
Uses real INDEC EPH microdata + Claude API as the decision engine per actor.

## Stack

- Elixir 1.19 / OTP 28
- PostgreSQL 16 (Docker)
- Ecto for persistence
- Req for HTTP
- NimbleCSV for EPH parsing
- Claude API (Haiku) for actor decisions

## Architecture

### Data flow

```
INDEC EPH files → EphLoader → PopulationSampler → ActorEnricher → DB (actors)
Measure → MeasureRunner → PromptBuilder + ClaudeClient → DB (decisions)
Decisions → Aggregator → Metrics by stratum/zone/employment/orientation
```

### Key design decisions

- **Aglomerados**: GBA = CABA (32) + Partidos del GBA (33). Always filter both.
- **Income**: Uses P47T (total personal income) not TOT_P12. Falls back to per-capita household income (ITF / household_size) for zero-income members.
- **Scientific notation**: EPH uses `5e+05` format for large numbers. The `parse_number/1` function handles this.
- **Rent**: EPH no longer publishes rent amounts (II4_1 is categorical yes/no). Rent is estimated from housing type in CanastaFamiliar.
- **CBT**: `@cbt_adult_equivalent` in CanastaFamiliar must be updated monthly from INDEC.
- **Profiles are JSONB**: Actor profiles are stored as JSONB maps with string keys. PromptBuilder reads string keys, not atoms.

## Commands

```bash
# Database
docker compose up -d
mix ecto.create && mix ecto.migrate
mix ecto.reset                    # drop + create + migrate

# Data
./scripts/download_eph.sh 3 2025  # download EPH T3 2025
mix sim.seed --n 5000             # seed actors

# Simulation
export CLAUDE_API_KEY=sk-ant-...
./scripts/run_simulation.sh "Description of the measure" --limit 100
mix sim.run --title "Title" --description "Description" --limit 100 --concurrency 30

# Console
iex -S mix
```

## Conventions

- Module prefix: `PopulationSimulator`
- EPH data files go in `priv/data/eph/` (gitignored)
- Migrations in `priv/repo/migrations/`
- Mix tasks in `lib/mix/tasks/sim.*.ex`
- All prompts are in Spanish (actors are Argentine citizens)
- Metric keys are strings (from raw SQL queries)

## Testing

No test suite yet. To verify the pipeline manually:

```elixir
# In iex -S mix
PopulationSimulator.Repo.aggregate(PopulationSimulator.Actors.Actor, :count)

# Check distributions
Ecto.Adapters.SQL.query!(PopulationSimulator.Repo,
  "SELECT stratum, COUNT(*) FROM actors GROUP BY 1 ORDER BY 2 DESC")
```
