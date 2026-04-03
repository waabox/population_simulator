# Population Simulator

Elixir/OTP application that simulates how the Greater Buenos Aires (GBA) population reacts to economic measures, using real INDEC EPH microdata and Claude API as the decision engine for each actor.

Actors have **memory**, **mood**, a **belief graph**, and **consciousness** — they accumulate experiences across measures, shift opinions, develop emergent concepts, converse with neighbors, and build evolving autobiographical narratives over time.

## How it works

1. **Data pipeline**: Loads INDEC EPH (Encuesta Permanente de Hogares) microdata for GBA (CABA + Conurbano), performs weighted sampling via PONDERA, and enriches each actor with synthetic financial, attitudinal, and crisis-memory variables calibrated from BCRA, UTDT, and Latinobarometro sources. Imputes income for non-response households (DECCFR=12) using decil medians.

2. **Stratification**: Actors are classified into 6 strata using INDEC methodology — household income per adult equivalent vs CBT/CBA thresholds derived from real INDEC socioeconomic stratification data. A RIPTE-based adjustment factor bridges the temporal gap between EPH data and current prices. Calibrated against INDEC 2do semestre 2025 targets: 6.3% indigencia, 28.2% pobreza.

3. **Populations**: Named groups of fixed actors. Create a population, assign actors to it, and run multiple measures against the same group to track evolution over time.

4. **Mood system**: Each actor has 5 mood dimensions (economic confidence, government trust, personal wellbeing, social anger, future outlook) that evolve with each measure. The LLM sees the actor's current mood and updates it based on how the measure affects them.

5. **Belief graph**: Each actor has a directed graph representing their mental model — nodes are concepts (inflation, employment, taxes, etc.) and edges are causal or emotional relationships with weights. The graph evolves with each measure: edges strengthen/weaken and new "emergent" nodes can appear when the LLM identifies new concepts.

6. **LLM evaluation**: When a measure is announced, each actor receives a first-person prompt built from their profile, mood, beliefs, history, and consciousness. They respond with a structured JSON decision (agreement, intensity, reasoning, personal impact, behavioral change, mood update, belief update).

7. **Consciousness** (3 layers):
   - **Mesa de café**: After each measure, actors are grouped into tables of 5-7 by zone + stratum affinity. One LLM call per table generates a full group conversation in Spanish rioplatense. The conversation influences each participant's mood and beliefs. Full dialogues are persisted.
   - **Autobiographical memory**: A ~200-word evolving narrative per actor that describes who they are and what they've experienced. Updated during introspection rounds.
   - **Metacognition**: Every 3 measures, each actor reflects on their recent decisions and conversations, updating their narrative and identifying patterns in their own behavior (self-observations).

8. **Metrics**: SQL-based aggregation computes approval rates segmented by stratum, zone, employment type, and political orientation. Mood and belief evolution are tracked over time per population.

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
mix sim.seed --n 1000 --population "1000 personas"
```

## Running simulations

### Basic measure (no consciousness)

```bash
export CLAUDE_API_KEY=sk-ant-...

mix sim.run \
  --title "Eliminacion de subsidios" \
  --description "El gobierno elimino los subsidios a las tarifas de luz, gas y agua." \
  --population "1000 personas"
```

### Measure + café conversations

```bash
# Single measure with café round (~1150 LLM calls)
./scripts/run_measure_with_cafe.sh \
  "El gobierno elimino los subsidios a las tarifas de luz, gas y agua." \
  --title "Eliminacion de subsidios" \
  --population "1000 personas"

# Or directly with mix:
mix sim.run \
  --title "Eliminacion de subsidios" \
  --description "El gobierno elimino los subsidios a las tarifas de luz, gas y agua." \
  --population "1000 personas" \
  --cafe
```

### Full consciousness cycle (3 measures)

Run 3 measures with café conversations. The 3rd triggers automatic introspection:

```bash
# Interactive — prompts for each measure
./scripts/run_full_cycle.sh "1000 personas"

# From a TSV file (tab-separated: title\tdescription)
MEASURES_FILE=scenarios.tsv ./scripts/run_full_cycle.sh "1000 personas"
```

Example `scenarios.tsv`:
```
Estabilidad del dólar	El dólar se estabiliza en $1390, carry trade rinde 18%, BCRA acumula reservas.
Suba de tarifas	El gobierno anuncia suba del 15% en tarifas de luz, gas y agua.
Aumento jubilaciones	Se aprueba aumento del 12% en jubilaciones y pensiones.
```

### Manual introspection

```bash
./scripts/run_introspection.sh "1000 personas"
```

## Querying results

### Mood and beliefs

```bash
mix sim.mood --population "1000 personas"
mix sim.mood --population "1000 personas" --history
mix sim.beliefs --population "1000 personas"
mix sim.beliefs --population "1000 personas" --emergent
mix sim.beliefs --population "1000 personas" --edge "taxes->employment" --history
```

### Café conversations

```bash
# Stats summary
./scripts/query_cafes.sh --stats

# All conversations for a zone
./scripts/query_cafes.sh --zone suburbs_outer

# An actor's café history
./scripts/query_cafes.sh --actor-id <uuid>

# Or with mix directly:
mix sim.cafe --measure-id <id>
mix sim.cafe --measure-id <id> --zone suburbs_outer
mix sim.cafe --actor-id <id>
```

### Introspection narratives

```bash
# Population summary
./scripts/query_introspection.sh

# Actor narrative history
./scripts/query_introspection.sh --actor-id <uuid>

# Random sample of narratives
./scripts/query_introspection.sh --sample 5

# Or with mix directly:
mix sim.introspect --actor-id <id>
mix sim.introspect --population "1000 personas"
```

### Resetting

```bash
# Clean simulation data (keep actors + initial state)
./scripts/clean_simulation.sh

# Full reset (remove everything)
./scripts/clean_simulation.sh --full
```

## Population management

```bash
mix sim.population.create --name "Panel A" --description "Test group"
mix sim.population.assign --name "Panel A" --zone caba_north,caba_south --age-max 35 --limit 100
mix sim.population.list
mix sim.population.info --name "Panel A"
```

## Calibration and variance

```bash
# Run same measure N times without persisting — check LLM consistency
mix sim.calibrate --measure-id <id> --runs 5 --sample 10
mix sim.calibrate --measure-id <id> --runs 3 --sample 5 --population "1000 personas"

# Analyze persisted results for artificial consensus or bias
mix sim.variance --population "1000 personas"
```

## Simulation cycle

```
=== MEASURE N ===
MeasureRunner  → 1000 individual decisions (profile + mood + beliefs + consciousness)
CafeRunner     → ~150 group conversations (5-7 actors per table)
               → mood/belief deltas applied per participant

=== MEASURE N+1 ===
MeasureRunner  → decisions (now with café summaries in prompt)
CafeRunner     → ~150 conversations

=== MEASURE N+2 ===
MeasureRunner  → decisions
CafeRunner     → ~150 conversations
IntrospectionRunner → 1000 reflections → autobiographical narratives

(cycle repeats every 3 measures)
```

**Cost per 3-measure cycle**: ~4,450 LLM calls (3,000 decisions + 450 cafés + 1,000 introspections).

## LLM grounding controls (5 layers)

1. **Rule constraints**: `ResponseValidator` enforces schema (types, ranges, lengths), caps intensity 1-10, limits belief deltas. Temperature 0.3.
2. **Bounded belief updates**: `BeliefGraph` caps emergent nodes at 10, total edges at 40, dampens edge weight changes (max 0.4/measure), decays unreinforced emergent nodes after 3 measures.
3. **Calibration loops**: `mix sim.calibrate` runs same measure N times without persisting — high variance = LLM hallucinating.
4. **Consistency checks**: `ConsistencyChecker` applies demographic rules post-response.
5. **Variance analysis**: `mix sim.variance` detects artificial consensus, emergent bias, mood clustering.

Café-specific constraints: mood deltas capped at +-1.0, max 2 belief edges per actor per café, no emergent nodes.

## Project structure

```
lib/population_simulator/
  data_pipeline/
    eph_loader.ex              # Parses INDEC EPH microdata + household income imputation
    population_sampler.ex      # Weighted sampling using PONDERA
    actor_enricher.ex          # Synthetic variables (financial, attitudinal, crisis memory)
    canasta_familiar.ex        # INDEC stratification + RIPTE income adjustment
  actors/
    actor.ex                   # Ecto schema + bulk insert
  populations/
    population.ex              # Named population schema
    actor_population.ex        # Many-to-many actor-population join
  simulation/
    measure.ex                 # Economic measure schema
    decision.ex                # Actor decision schema
    actor_mood.ex              # Mood snapshot (5 dimensions + narrative)
    actor_belief.ex            # Belief graph snapshot
    actor_summary.ex           # Autobiographical narrative + self-observations
    belief_graph.ex            # Graph construction, delta application, humanization
    prompt_builder.ex          # LLM prompt (arities 2/3/4/5)
    measure_runner.ex          # Orchestrates decisions via Task.async_stream
    cafe_grouper.ex            # Groups actors by zone+stratum into tables of 5-7
    cafe_prompt_builder.ex     # Builds group conversation prompt
    cafe_response_validator.ex # Validates café LLM responses
    cafe_runner.ex             # Orchestrates café round
    cafe_session.ex            # Café conversation schema (full dialogue)
    cafe_effect.ex             # Per-actor mood/belief deltas from café
    introspection_prompt_builder.ex  # Builds reflection prompt
    introspection_runner.ex    # Orchestrates introspection round
    consciousness_loader.ex    # Loads narrative + café summaries for prompts
    response_validator.ex      # Schema validation for decision responses
    consistency_checker.ex     # Demographic consistency post-checks
  llm/
    claude_client.ex           # Anthropic Messages API wrapper
  metrics/
    aggregator.ex              # SQL aggregation (decisions, mood, beliefs)
lib/mix/tasks/
  sim.seed.ex                  # Seed actors from EPH data
  sim.run.ex                   # Run measure [--cafe for consciousness]
  sim.cafe.ex                  # Query café conversations
  sim.introspect.ex            # Run/query introspection
  sim.mood.ex                  # Query mood averages and evolution
  sim.beliefs.ex               # Query belief graphs
  sim.beliefs.init.ex          # Generate archetype belief templates
  sim.calibrate.ex             # LLM response variance analysis
  sim.variance.ex              # Detect artificial consensus/bias
  sim.population.*.ex          # Population management
scripts/
  download_eph.sh              # Download EPH microdata from INDEC
  run_simulation.sh            # Basic simulation runner
  run_measure_with_cafe.sh     # Single measure + café
  run_full_cycle.sh            # 3 measures + café + introspection
  run_introspection.sh         # Manual introspection trigger
  query_cafes.sh               # Query café conversations
  query_introspection.sh       # Query actor narratives
  clean_simulation.sh          # Reset simulation data
priv/data/
  belief_templates/            # 8 archetype belief graph JSON templates
  eph/                         # INDEC EPH microdata files (gitignored)
```

## Data sources

| Source | Description |
|--------|-------------|
| [INDEC EPH](https://www.indec.gob.ar) | Encuesta Permanente de Hogares microdata (individual + household) |
| [INDEC CBT/CBA](https://www.indec.gob.ar/indec/web/Nivel4-Tema-4-43-149) | Canasta Básica Total/Alimentaria — poverty/indigence lines |
| [RIPTE](https://www.argentina.gob.ar/trabajo/seguridadsocial/ripte) | Wage index for income temporal adjustment |
| [BCRA](https://www.bcra.gob.ar) | Financial inclusion report — banking and dollarization rates |
| [UTDT](https://www.utdt.edu) | Government confidence index by socioeconomic level |
| [Latinobarometro](https://www.latinobarometro.org) | Attitudinal variables for Argentina |

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLAUDE_API_KEY` | Yes | - | Anthropic API key |
| `CLAUDE_MODEL` | No | `claude-haiku-4-5-20251001` | Model for LLM calls |
| `LLM_CONCURRENCY` | No | `30` | Max concurrent API calls |
| `MEASURES_FILE` | No | - | TSV file for `run_full_cycle.sh` |
