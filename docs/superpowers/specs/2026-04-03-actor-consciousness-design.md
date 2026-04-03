# Actor Consciousness — Design Spec

## Overview

Add three layers of consciousness to simulated actors:
1. **Autobiographical memory** — A persistent, evolving narrative summary of who the actor is and what they've experienced
2. **Metacognition** — Periodic introspection where actors reflect on their own patterns and biases
3. **Social interaction** — "Mesa de café" group conversations after each measure, where actors influence each other's moods and beliefs

## Architecture

### Simulation Cycle

```
=== MEDIDA N ===
MeasureRunner: 1000 individual decisions (existing)
CafeRunner: ~150 group conversations → mood/belief deltas + persisted dialogues

=== MEDIDA N+1 ===
MeasureRunner: decisions (now with café summaries in prompt)
CafeRunner: ~150 group conversations

=== MEDIDA N+2 ===
MeasureRunner: decisions
CafeRunner: ~150 group conversations
IntrospectionRunner: 1000 individual reflections → narratives + self_observations

(cycle repeats every 3 measures)
```

### Cost per 3-measure cycle

- Measures: 3 × 1000 = 3,000 LLM calls
- Cafés: 3 × ~150 = ~450 LLM calls
- Introspection: 1 × 1000 = 1,000 LLM calls
- **Total: ~4,450 calls** (vs 3,000 without consciousness — +48%)

## Data Model

### `actor_summaries`

Stores the autobiographical narrative. One row per introspection version (not overwritten).

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | PK |
| `actor_id` | UUID | FK to actors |
| `narrative` | TEXT | ~200 word autobiographical summary in Spanish |
| `self_observations` | JSON | Array of strings — patterns the actor notices about themselves |
| `version` | INTEGER | Increments each introspection (1, 2, 3...) |
| `measure_id` | UUID | The measure that triggered this introspection |
| `inserted_at` | DATETIME | |

### `cafe_sessions`

One row per group conversation (mesa de café).

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | PK |
| `measure_id` | UUID | FK to measures |
| `group_key` | STRING | Affinity key, e.g. "suburbs_outer:low" |
| `participant_ids` | JSON | Array of actor UUIDs |
| `participant_names` | JSON | Map of actor_id → fictitious name used in conversation |
| `conversation` | JSON | Full dialogue array: [{actor_id, name, message}, ...] |
| `conversation_summary` | TEXT | Short summary for use in future prompts |
| `inserted_at` | DATETIME | |

### `cafe_effects`

Per-participant effects from a café session.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | PK |
| `cafe_session_id` | UUID | FK to cafe_sessions |
| `actor_id` | UUID | FK to actors |
| `mood_deltas` | JSON | {economic_confidence: +0.5, social_anger: -0.3, ...} |
| `belief_deltas` | JSON | {modified_edges: [...], new_nodes: [...]} |
| `inserted_at` | DATETIME | |

## Mesa de Café — Group Conversation

### Grouping Criteria (CafeGrouper)

- **Primary**: Same zone (caba_north, caba_south, suburbs_inner, suburbs_middle, suburbs_outer)
- **Secondary**: Similar stratum (destitute+low, lower_middle+middle, upper_middle+upper)
- **Table size**: 5-7 actors
- Groups larger than 7 are split into sub-tables

### LLM Prompt (CafePromptBuilder)

Input per table:
- The measure just evaluated
- For each participant (5-7): fictitious name, summarized profile (stratum, zone, employment, age), their decision on the measure (agreement/rejection + intensity + reasoning), current mood (5 dimensions)
- Instruction: generate the conversation and how each person influences the others

### LLM Output (JSON)

```json
{
  "conversation": [
    {
      "actor_id": "uuid",
      "name": "María",
      "message": "A mí el dólar estable me viene bien para el alquiler, pero no llego a fin de mes igual..."
    },
    {
      "actor_id": "uuid",
      "name": "Jorge",
      "message": "Vos decís que está estable pero yo en el super pago cada vez más."
    }
  ],
  "conversation_summary": "2-3 sentence summary of what was discussed",
  "effects": [
    {
      "actor_id": "uuid",
      "mood_deltas": {
        "economic_confidence": 0.5,
        "social_anger": -0.3
      },
      "belief_deltas": {
        "modified_edges": [{"from": "dollar_stability", "to": "economic_confidence", "weight_delta": 0.2}],
        "new_nodes": []
      }
    }
  ]
}
```

### Grounding Constraints

- Mood deltas capped at +-1.0 per dimension per café
- Belief deltas: max 2 modified edges per actor per café
- No emergent nodes allowed (only in direct measures)
- Temperature 0.3
- ResponseValidator validates output schema
- All prompts and conversations in Spanish

## Introspection

### Trigger

Every 3 measures, automatically after the café round.

### LLM Prompt (IntrospectionPromptBuilder)

Input per actor:
- Actor profile
- Previous autobiographical narrative (empty if first time)
- Last 3 decisions with reasoning
- Last café conversation summaries (summary only, not full dialogue)
- Current mood and how it changed
- Instruction: "You are this citizen. Reflect on what happened to you, what patterns you notice in your reactions, and rewrite your personal narrative."

### LLM Output

```json
{
  "narrative": "Soy María, 42 años, vivo en Lanús. Trabajo en negro limpiando casas...",
  "self_observations": [
    "Tendencia al pesimismo económico",
    "Fuerte identificación con su grupo social",
    "Desconexión entre indicadores macro y realidad personal"
  ]
}
```

### Constraints

- Narrative: max 200 words
- Self_observations: max 5 items
- Temperature 0.3

## PromptBuilder Integration

New arity `build/5` adds consciousness context:

```
[Demographic profile]
[Who you are — autobiographical narrative]
[What you observe about yourself — self_observations]
[Current mood — 5 dimensions]
[Beliefs — belief graph]
[Recent neighbor conversations — last 2 café summaries]
[Recent decision history]
---
[The measure to evaluate]
```

Token budget for consciousness block: ~300-400 tokens.

Backwards compatible: actors without a narrative yet use existing arity 4.

## New Modules

| Module | Responsibility |
|--------|----------------|
| `CafeRunner` | Orchestrates café round: groups actors, dispatches LLM calls, persists dialogues and effects |
| `CafeGrouper` | Groups actors by zone + stratum affinity, partitions into tables of 5-7 |
| `CafePromptBuilder` | Builds group conversation prompt with profiles + decisions + moods |
| `IntrospectionRunner` | Orchestrates individual reflection, generates narratives |
| `IntrospectionPromptBuilder` | Builds prompt with history + cafés + mood for reflection |
| `ConsciousnessLoader` | Loads narrative + observations + café summaries for PromptBuilder |

## Mix Tasks

```bash
# Run measure + café in one command
mix sim.run --title "..." --description "..." --population "..." --cafe

# Run introspection manually (or auto-triggered every 3 measures)
mix sim.introspect --population "1000 personas"

# Query café conversations
mix sim.cafe --measure-id <id>
mix sim.cafe --measure-id <id> --zone suburbs_outer
mix sim.cafe --actor-id <id>

# Query actor introspection history
mix sim.introspection --actor-id <id>
mix sim.introspection --population "1000 personas"
```

## Validation Targets

After implementing, verify:
- Café conversations are coherent and reflect participant profiles
- Mood deltas from cafés are within bounds (+-1.0)
- Belief deltas respect max 2 edges per actor per café
- Introspection narratives evolve meaningfully across versions
- Actors with narratives produce qualitatively different decisions than those without
- Total cycle cost stays within ~4,500 calls per 3 measures
