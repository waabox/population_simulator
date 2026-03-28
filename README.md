# Population Simulator

Elixir/OTP application that simulates how the Greater Buenos Aires (GBA) population reacts to economic measures, using real INDEC EPH microdata and Claude API as the decision engine for each actor.

## How it works

1. **Data pipeline**: Loads INDEC EPH (Encuesta Permanente de Hogares) microdata for GBA (CABA + Conurbano), performs weighted sampling via PONDERA, and enriches each actor with synthetic financial, attitudinal, and crisis-memory variables calibrated from BCRA, UTDT, and Latinobarometro sources.

2. **Actor system**: Each actor is a GenServer holding a rich demographic profile (age, income, education, employment sector, children, housing, political orientation, dollar savings, government trust, etc.).

3. **LLM evaluation**: When a measure is announced, each actor receives a first-person prompt built from their profile and responds with a structured JSON decision (agreement, intensity 1-10, reasoning, personal impact, behavioral change).

4. **Metrics**: SQL-based aggregation computes approval rates segmented by socioeconomic stratum, geographic zone, employment type, and political orientation.

## Prerequisites

- Elixir 1.19+
- Docker (for PostgreSQL)
- Anthropic API key

## Setup

```bash
# Start PostgreSQL
docker compose up -d

# Install dependencies and setup database
mix deps.get
mix ecto.create
mix ecto.migrate

# Download EPH data from INDEC (T3 2025)
./scripts/download_eph.sh 3 2025

# Seed 5000 actors from real EPH data
mix sim.seed --n 5000
```

## Running a simulation

```bash
export CLAUDE_API_KEY=sk-ant-...

# Using the script
./scripts/run_simulation.sh "El gobierno eliminó los subsidios a las tarifas de luz, gas y agua." --limit 100

# Or directly with mix
mix sim.run \
  --titulo "Eliminación de subsidios" \
  --descripcion "El gobierno eliminó los subsidios a las tarifas de luz, gas y agua para los hogares del AMBA." \
  --limit 100 \
  --concurrency 30
```

## Project structure

```
lib/population_simulator/
  data_pipeline/
    eph_loader.ex           # Parses INDEC EPH microdata (individual + hogar)
    population_sampler.ex   # Weighted sampling using PONDERA
    actor_enricher.ex       # Synthetic variables (financial, attitudinal, crisis memory)
    canasta_familiar.ex     # CBT (Canasta Basica Total) classification
  actors/
    actor.ex                # Ecto schema + bulk insert
    actor_server.ex         # GenServer per actor
    population_manager.ex   # DynamicSupervisor lifecycle management
  simulation/
    measure.ex              # Economic measure schema
    decision.ex             # Actor decision schema
    prompt_builder.ex       # LLM prompt generation from profiles
    measure_runner.ex       # Orchestrates concurrent evaluation via Task.async_stream
  llm/
    claude_client.ex        # Anthropic Messages API wrapper
  metrics/
    aggregator.ex           # SQL aggregation by estrato, zona, empleo, orientation
scripts/
  download_eph.sh           # Downloads EPH microdata from INDEC
  run_simulation.sh         # Convenience wrapper for running simulations
```

## Data sources

| Source | Description |
|--------|-------------|
| [INDEC EPH](https://www.indec.gob.ar) | Encuesta Permanente de Hogares microdata (individual + household) |
| [BCRA](https://www.bcra.gob.ar) | Financial inclusion report — banking and dollarization rates |
| [UTDT](https://www.utdt.edu) | Government confidence index by socioeconomic level |
| [Latinobarometro](https://www.latinobarometro.org) | Attitudinal variables for Argentina |

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLAUDE_API_KEY` | Yes | — | Anthropic API key |
| `CLAUDE_MODEL` | No | `claude-haiku-4-5-20251001` | Model for LLM calls |
| `LLM_CONCURRENCY` | No | `30` | Max concurrent API calls |
