# Population Simulator

Elixir/OTP application that simulates how the Greater Buenos Aires (GBA) population reacts to economic measures, using real INDEC EPH microdata and Claude API as the decision engine for each actor.

Actors have **memory**, **mood**, and a **belief graph** — they accumulate experiences across measures, shift opinions, and develop emergent concepts over time.

## How it works

1. **Data pipeline**: Loads INDEC EPH (Encuesta Permanente de Hogares) microdata for GBA (CABA + Conurbano), performs weighted sampling via PONDERA, and enriches each actor with synthetic financial, attitudinal, and crisis-memory variables calibrated from BCRA, UTDT, and Latinobarometro sources.

2. **Populations**: Named groups of fixed actors. Create a population, assign actors to it, and run multiple measures against the same group to track evolution over time.

3. **Mood system**: Each actor has 5 mood dimensions (economic confidence, government trust, personal wellbeing, social anger, future outlook) that evolve with each measure. The LLM sees the actor's current mood and updates it based on how the measure affects them.

4. **Belief graph**: Each actor has a directed graph representing their mental model — nodes are concepts (inflation, employment, taxes, etc.) and edges are causal or emotional relationships with weights. The graph evolves with each measure: edges strengthen/weaken and new "emergent" nodes can appear when the LLM identifies new concepts.

5. **Memory**: Actors carry their history of past decisions (what they agreed/disagreed with) and a narrative describing their emotional state. This context is included in every prompt, so actors react consistently with their accumulated experience.

6. **LLM evaluation**: When a measure is announced, each actor receives a first-person prompt built from their profile, mood, beliefs, and history. They respond with a structured JSON decision (agreement, intensity, reasoning, personal impact, behavioral change, mood update, belief update).

7. **Metrics**: SQL-based aggregation computes approval rates segmented by stratum, zone, employment type, and political orientation. Mood and belief evolution are tracked over time per population.

## Prerequisites

- Elixir 1.19+
- Anthropic API key

## Setup

```bash
# Install dependencies and setup database
mix deps.get
mix ecto.create
mix ecto.migrate

# Download EPH data from INDEC (T3 2025)
./scripts/download_eph.sh 3 2025

# Generate belief graph templates (8 LLM calls)
export CLAUDE_API_KEY=sk-ant-...
mix sim.beliefs.init

# Seed 1000 actors with a named population
mix sim.seed --n 1000 --population "My Panel"
```

## Running a simulation

```bash
export CLAUDE_API_KEY=sk-ant-...

# Run a measure against a population
mix sim.run \
  --title "Eliminacion de subsidios" \
  --description "El gobierno elimino los subsidios a las tarifas de luz, gas y agua." \
  --population "My Panel"

# Run without population (all actors, with optional limit)
mix sim.run \
  --title "Title" \
  --description "Description" \
  --limit 100 \
  --concurrency 30
```

## Tracking evolution

```bash
# View current mood averages
mix sim.mood --population "My Panel"

# View mood evolution across measures
mix sim.mood --population "My Panel" --history

# View belief graph summary (top causal/emotional edges)
mix sim.beliefs --population "My Panel"

# View emergent nodes (concepts created by the LLM)
mix sim.beliefs --population "My Panel" --emergent

# Track a specific belief edge over time
mix sim.beliefs --population "My Panel" --edge "taxes->employment" --history
```

## Population management

```bash
# Create a named population
mix sim.population.create --name "Panel A" --description "Test group"

# Assign actors with filters
mix sim.population.assign --name "Panel A" --zone caba_north,caba_south --age-max 35 --limit 100

# List all populations
mix sim.population.list

# Show population composition
mix sim.population.info --name "Panel A"
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
  populations/
    population.ex           # Named population schema
    actor_population.ex     # Many-to-many actor-population join
  simulation/
    measure.ex              # Economic measure schema
    decision.ex             # Actor decision schema
    actor_mood.ex           # Mood snapshot schema (5 dimensions + narrative)
    actor_belief.ex         # Belief graph snapshot schema
    belief_graph.ex         # Graph construction, delta application, humanization
    prompt_builder.ex       # LLM prompt generation (profile + mood + beliefs + history)
    measure_runner.ex       # Orchestrates concurrent evaluation via Task.async_stream
  llm/
    claude_client.ex        # Anthropic Messages API wrapper
  metrics/
    aggregator.ex           # SQL aggregation (decisions, mood, beliefs)
lib/mix/tasks/
  sim.seed.ex               # Seed actors from EPH data
  sim.run.ex                # Run a measure against actors
  sim.population.create.ex  # Create a named population
  sim.population.list.ex    # List all populations
  sim.population.assign.ex  # Assign actors to a population
  sim.population.info.ex    # Show population composition
  sim.mood.ex               # Query mood averages and evolution
  sim.beliefs.ex            # Query belief graphs
  sim.beliefs.init.ex       # Generate archetype belief templates via LLM
priv/data/
  belief_templates/         # 8 archetype belief graph JSON templates
  eph/                      # INDEC EPH microdata files (gitignored)
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
| `CLAUDE_API_KEY` | Yes | - | Anthropic API key |
| `CLAUDE_MODEL` | No | `claude-haiku-4-5-20251001` | Model for LLM calls |
| `LLM_CONCURRENCY` | No | `30` | Max concurrent API calls |
