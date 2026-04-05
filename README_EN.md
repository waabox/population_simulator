# Population Simulator

Elixir/OTP application that simulates how the Greater Buenos Aires (GBA) population reacts to economic measures, using real INDEC EPH microdata and Claude API as the decision engine for each actor.

Actors have **memory**, **mood**, a **belief graph**, and **consciousness** — they accumulate experiences across measures, shift opinions, develop emergent concepts, converse with neighbors, form social bonds, and build evolving autobiographical narratives over time.

![Dashboard](site/dashboard.png)

![Cafés](site/cafes.png)

## How it works

1. **Data pipeline**: Loads INDEC EPH (Encuesta Permanente de Hogares) microdata for GBA (CABA + Conurbano), performs weighted sampling via PONDERA, and enriches each actor with synthetic financial, attitudinal, and crisis-memory variables calibrated from BCRA, UTDT, and Latinobarometro sources. Imputes income for non-response households (DECCFR=12) using decile medians.

2. **Stratification**: Actors are classified into 6 strata using INDEC methodology — household income per adult equivalent vs CBT/CBA thresholds derived from real INDEC socioeconomic stratification data. A RIPTE-based adjustment factor bridges the temporal gap between EPH data and current prices. Calibrated against INDEC 2nd semester 2025 targets: 6.3% indigence, 28.2% poverty.

3. **Populations**: Named groups of fixed actors. Create a population, assign actors to it, and run multiple measures against the same group to track evolution over time.

4. **Mood system**: Each actor has 5 mood dimensions (economic confidence, government trust, personal wellbeing, social anger, future outlook) that evolve with each measure. The LLM sees the actor's current mood and updates it based on how the measure affects them.

5. **Belief graph**: Each actor has a directed graph representing their mental model — nodes are concepts (inflation, employment, taxes, etc.) and edges are causal or emotional relationships with weights. The graph evolves with each measure: edges strengthen/weaken and new "emergent" nodes can appear when the LLM identifies new concepts.

6. **LLM evaluation**: When a measure is announced, each actor receives a first-person prompt built from their profile, mood, beliefs, history, and consciousness. They respond with a structured JSON decision (agreement, intensity, reasoning, personal impact, behavioral change, mood update, belief update).

7. **Consciousness** (8 layers):
   - **Mesa de café**: After each measure, actors are grouped into tables of 5-7 by zone + stratum affinity. One LLM call per table generates a full group conversation in Argentine Spanish. The conversation influences each participant's mood and beliefs. Full dialogues are persisted.
   - **Autobiographical memory**: An evolving ~200-word narrative per actor describing who they are and what they've experienced. Updated during introspection rounds.
   - **Metacognition**: Every 3 measures, each actor reflects on their recent decisions and conversations, updates their narrative, and identifies patterns in their own behavior (self-observations).
   - **Cognitive dissonance**: A 0-1 index measuring contradiction between an actor's mood/beliefs/history and their decisions. High dissonance increases LLM temperature (more volatility). Accumulated unresolved dissonance becomes social anger. During introspection, actors confront their contradictions.
   - **Personal events**: ~20% of actors receive an LLM-generated life event after each measure (measure-derived or personal). Events modify mood and profile (employment, income, etc.) and decay over 1-6 measures.
   - **Social bonds**: Actors who share 3+ cafés form persistent bonds. Café tables prioritize seating bonded actors together. Bonds decay without reinforcement.
   - **Theory of mind**: After each café, actors perceive their group's mood and identify 1-2 referents who influenced them. These perceptions are injected into future prompts.
   - **Intentions**: During introspection, actors generate free-form intentions ("I'm going to look for a formal job", "I'm going to buy dollars"). The LLM resolves them in the next introspection. Effects are applied to the actor's profile.

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

## Web interface

```bash
mix phx.server
```

Open **http://localhost:4000**. The UI has 5 sections:

- **Dashboard** — Mood, beliefs, approval, dissonance, events, bonds, perceptions, intentions, café preview
- **Actors** — Filterable directory with detail panel (narrative, intentions, events, bonds, perceptions, dissonance)
- **Cafés** — Chat-style conversation viewer with table selector and zone/measure filters
- **New Simulation** — Form to run measures with per-phase checkboxes (events, café, introspection)
- **Settings** — API key and model

## Running simulations

### Basic measure (no consciousness)

```bash
export CLAUDE_API_KEY=sk-ant-...

mix sim.run \
  --title "Subsidy removal" \
  --description "The government removed subsidies for electricity, gas and water." \
  --population "1000 personas"
```

### Measure + café conversations

```bash
# Single measure with café round (~1350 LLM calls)
./scripts/run_measure_with_cafe.sh \
  "The government removed subsidies for electricity, gas and water." \
  --title "Subsidy removal" \
  --population "1000 personas"

# Or directly with mix:
mix sim.run \
  --title "Subsidy removal" \
  --description "The government removed subsidies for electricity, gas and water." \
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

# Or with mix:
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

# Analyze persisted results for artificial consensus or bias
mix sim.variance --population "1000 personas"
```

## Simulation cycle

```
=== MEASURE N ===
MeasureRunner       → 1000 individual decisions (profile + mood + beliefs + consciousness)
DissonanceCalc      → dissonance index per actor (adjusts LLM temperature)
EventGenerator      → ~200 personal events for vulnerable actors
CafeRunner          → ~150 group conversations (5-7 actors per table)
AffinityTracker     → updates bonds between pairs
TheoryOfMindBuilder → group perceptions + referents

=== MEASURE N+1 ===
(same flow, now with bonds, active events, and perceptions in prompts)

=== MEASURE N+2 ===
(same flow)
IntrospectionRunner → 1000 reflections → narratives + intentions
IntentionExecutor   → executes resolved intentions → updates profiles

(cycle repeats every 3 measures)
```

**Cost per measure**: ~1350 LLM calls (1000 decisions + ~200 events + ~150 cafés).
**Cost per 3-measure cycle**: ~5050 calls (4050 + 1000 introspections).

## LLM grounding controls (5 layers)

1. **Rule constraints**: `ResponseValidator` enforces schema validation (types, ranges, lengths), caps intensity 1-10, limits belief deltas. Temperature 0.3.
2. **Bounded belief updates**: `BeliefGraph` caps emergent nodes at 10, total edges at 40, dampens weight changes (max 0.4/measure), decays unreinforced emergent nodes after 3 measures.
3. **Calibration loops**: `mix sim.calibrate` runs same measure N times without persisting — high variance = LLM hallucinating.
4. **Consistency checks**: `ConsistencyChecker` applies demographic rules post-response.
5. **Variance analysis**: `mix sim.variance` detects artificial consensus, emergent bias, mood clustering.

Café-specific constraints: mood deltas capped at +-1.0, max 2 belief edges per actor per café, no new nodes.

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

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Copyright 2026 Emiliano Arango. Licensed under the [Apache License 2.0](LICENSE).
