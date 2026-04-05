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
- **Prompt arities**: `PromptBuilder.build/2` (basic), `build/3` (with mood), `build/4` (with mood + beliefs), `build/5` (with mood + beliefs + consciousness). MeasureRunner selects the appropriate arity based on available data.
- **Consciousness**: 3 layers — autobiographical narrative (actor_summaries, updated every 3 measures via IntrospectionRunner), social interaction (cafe_sessions with full dialogue, CafeRunner groups by zone+stratum into tables of 5-7), metacognition (self_observations in actor_summaries). PromptBuilder.build/5 injects narrative + observations + café summaries.
- **Cognitive dissonance**: DissonanceCalculator computes a 0-1 index per decision by comparing mood (anger/trust/confidence) and history against the decision. High dissonance raises LLM temperature (0.3 → up to 0.7) for that actor, making responses more volatile. Accumulated dissonance (>0.5 for 3+ measures) auto-increments social_anger. IntrospectionPromptBuilder confronts actors with their contradictions every 3 measures.
- **Personal events**: EventGenerator selects ~20% of actors per measure (weighted by vulnerability: low stratum, high anger, unemployed, high dissonance). LLM generates a personalized event per actor — can be measure-derived or a life event. Events modify mood and profile (employment, income, etc.) and decay over 1-6 measures. Max 3 active events per actor. EventDecayer ticks remaining counter each measure.
- **Social bonds**: AffinityTracker tracks emergent relationships between actors. Pairs who share 3+ cafés form bonds (max 10 per actor). CafeGrouper prefers seating bonded actors together. CafePromptBuilder annotates bonds so the LLM generates dialogue with social history. Affinity decays -0.1 per measure without shared café; bonds deleted at 0.
- **Theory of mind**: After each café, TheoryOfMindBuilder computes group mood perception (agreement ratio + dominant emotion, no LLM) and extracts referents (1-2 per actor) from the café LLM response. Perceptions are persisted in actor_perceptions and injected into future prompts so actors reason about their social environment.
- **Intentions**: During introspection, actors generate free-form intentions (max 2 active). The LLM decides the action and profile_effects (employment, income, dollars, etc.). In the next introspection, the LLM resolves pending intentions (executed/frustrated). IntentionExecutor validates effects against allowed fields, clamps income_delta to +-50%, and applies changes to the actor profile. Intentions expire after 2 introspections without resolution.
- **UI**: Phoenix LiveView with 5 pages. Dashboard shows mood, beliefs, approval, dissonance, events, bonds, perceptions, intentions, and café previews. CafesLive page has chat-style conversation viewer with mesa selector. ActorsLive detail panel shows full consciousness state per actor. RunMeasureLive supports per-phase checkboxes (events, café, introspection) with multi-phase progress display.

### LLM Grounding Controls (5 layers)

1. **Rule constraints**: `ResponseValidator` enforces schema (types, ranges, lengths), caps intensity 1-10, limits belief deltas (max 3 nodes, 5 edges per measure), validates node IDs (snake_case, max 30 chars). Temperature set to 0.3.
2. **Bounded belief updates**: `BeliefGraph` caps emergent nodes at 10, total edges at 40, dampens edge weight changes (max 0.4 per measure), decays unreinforced emergent nodes after 3 measures.
3. **Calibration loops**: `mix sim.calibrate` runs same measure N times for sample actors without persisting — reports agreement consistency and per-dimension variance. High variance = LLM hallucinating.
4. **Consistency checks**: `ConsistencyChecker` applies demographic rules post-response (e.g., destitute + austerity → cap economic_confidence, floor social_anger; opposing orientation → cap intensity).
5. **Variance analysis**: `mix sim.variance` analyzes persisted results for artificial consensus (>90% agreement), emergent node bias (>50% actors share concept), mood clustering (low dimension variance), belief homogenization.

## Database Schema

### Tables

- **actors** — demographic profile, stratum, zone, age, employment, orientation
- **cafe_sessions** — group conversation per table per measure (full dialogue + summary)
- **cafe_effects** — per-actor mood/belief deltas from café conversations
- **actor_summaries** — autobiographical narrative versions (narrative + self_observations)
- **populations** — named groups (name unique)
- **actor_populations** — many-to-many (actor_id, population_id, unique index)
- **measures** — title, description, optional population_id
- **decisions** — actor reaction to a measure (agreement, intensity, reasoning, etc.)
- **actor_moods** — mood snapshot per actor per decision (5 dimensions + narrative)
- **actor_beliefs** — belief graph snapshot per actor per decision (JSON graph)
- **actor_events** — personal life events with mood impact, profile effects, and decay duration

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

# Calibration & Variance
mix sim.calibrate --measure-id <id> --runs 5 --sample 10
mix sim.calibrate --measure-id <id> --runs 3 --sample 5 --population "My Panel"
mix sim.variance --population "My Panel"

# Café conversations
mix sim.run --title "..." --description "..." --population "..." --cafe
mix sim.cafe --measure-id <id>
mix sim.cafe --measure-id <id> --zone suburbs_outer
mix sim.cafe --actor-id <id>

# Introspection
mix sim.introspect --actor-id <id>
mix sim.introspect --population "1000 personas"
mix sim.introspect --run --population "1000 personas"

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
| `ResponseValidator` | Schema validation + rule constraints for LLM responses (pre-persistence) |
| `ConsistencyChecker` | Demographic consistency checks: stratum/orientation vs mood/intensity |
| `BeliefGraph` | Graph construction, delta application, template variations, humanization for prompts, edge damping, emergent decay |
| `ActorMood` | Mood schema, initial derivation from profile, LLM response parsing |
| `ActorBelief` | Belief schema, initial/update factory functions |
| `PromptBuilder` | Builds prompts with profile + mood + beliefs + history + consciousness (arities 2/3/4/5) |
| `MeasureRunner` | Orchestrates concurrent evaluation, loads mood/beliefs/consciousness, persists all results |
| `Aggregator` | SQL metrics for decisions, mood evolution, belief summary, emergent nodes |
| `CafeRunner` | Orchestrates café round: groups actors, LLM calls, persists dialogues + effects |
| `CafeGrouper` | Groups actors by zone+stratum into tables of 5-7 |
| `CafePromptBuilder` | Builds group conversation prompt for café tables |
| `CafeResponseValidator` | Validates café LLM response: mood deltas +-1.0, max 2 belief edges, no new nodes |
| `IntrospectionRunner` | Periodic reflection every 3 measures, generates autobiographical narratives |
| `ConsciousnessLoader` | Loads narrative + observations + café summaries + dissonance for PromptBuilder |
| `DissonanceCalculator` | Cognitive dissonance index, temperature scaling, confrontation triggers |
| `EventGenerator` | Select vulnerable actors, generate personal events via LLM |
| `EventDecayer` | Decay event duration, compute aggregate mood impact |
| `EventResponseValidator` | Validate event LLM response: mood +-2.0, profile fields, duration 1-6 |
| `AffinityTracker` | Emergent social bonds: formation, decay, bond-aware queries |
| `TheoryOfMindBuilder` | Group mood computation, referent extraction and persistence |
| `IntentionExecutor` | Apply profile effects from resolved intentions, validate, expire |
| `ConsciousnessAggregator` | SQL queries for consciousness UI: dissonance, events, bonds, perceptions, intentions |

## Use Cases

- [LLM Grounding Controls](.claude/docs/use-cases/llm-grounding-controls.md) — 5-layer system to prevent the LLM from hallucinating sociological patterns

## Testing

Unit tests for validation and belief bounds:

```bash
mix test
```

To verify the pipeline manually:

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
