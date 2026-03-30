# Belief Graph — Actor Consciousness (Phase 1)

## Context

The population simulator has actors with demographic profiles, evolving mood (5 dimensions), and decision history. Actors react to measures but lack an internal model of how the world works. This design adds a **belief graph** — a directed graph where nodes are concepts and edges are perceived causal or emotional relationships. The graph represents the actor's mental model and evolves with each measure.

This is Phase 1 of a 3-phase consciousness system:
1. **Belief Graph** (this spec) — internal model of how the world works
2. **Emergent Personality** (future) — synthesized identity from beliefs + mood + history
3. **Spontaneous Opinion** (future) — actor-initiated reflections beyond reactions

## Data Model

### New Table: `actor_beliefs`

| Field       | Type         | Constraints                              |
|-------------|--------------|------------------------------------------|
| id          | UUID         | PK                                       |
| actor_id    | UUID         | FK -> actors, not null                    |
| decision_id | UUID         | FK -> decisions, nullable (null = initial)|
| measure_id  | UUID         | FK -> measures, nullable (null = initial) |
| graph       | map (JSON)   | Full belief graph                        |
| timestamps  | utc_datetime |                                          |
| index       |              | (actor_id, inserted_at)                  |

### Graph JSON Structure

```json
{
  "nodes": [
    {"id": "inflation", "type": "core"},
    {"id": "employment", "type": "core"},
    {"id": "energy_costs", "type": "emergent", "added_at": "Aumento de tarifas"}
  ],
  "edges": [
    {
      "from": "taxes",
      "to": "employment",
      "type": "causal",
      "weight": -0.7,
      "description": "More taxes reduce employment"
    },
    {
      "from": "inflation",
      "to": "anger",
      "type": "emotional",
      "weight": 0.8,
      "description": "Inflation makes me angry"
    }
  ]
}
```

### Field Definitions

- **nodes[].id**: snake_case string identifier
- **nodes[].type**: "core" (from base set) or "emergent" (added by LLM)
- **nodes[].added_at**: (emergent only) measure title that triggered creation
- **edges[].from / to**: node ids
- **edges[].type**: "causal" (perceived cause-effect) or "emotional" (feeling triggered by concept)
- **edges[].weight**: -1.0 to 1.0. Negative = inverse/negative relationship. Positive = direct/positive.
- **edges[].description**: short text explaining the relationship in the actor's voice

### Core Nodes (15)

`inflation`, `employment`, `taxes`, `dollar`, `state_role`, `social_welfare`, `pensions`, `wages`, `security`, `education`, `healthcare`, `corruption`, `foreign_trade`, `utility_rates`, `private_property`

Emergent nodes can be added by the LLM when a measure introduces concepts not covered by core nodes.

### Typical Graph Size

- 15 core nodes + 0-5 emergent nodes
- 15-25 edges (sparse — only relationships the actor perceives as relevant)
- Not all nodes need edges. An actor may have no opinion about `foreign_trade`.

## Initialization

### Archetype-Based Templates

Generating belief graphs via LLM per actor is too expensive at scale. Instead:

1. Define 8 archetypes by `stratum` x `political_orientation`:

| Archetype          | Stratum              | Orientation |
|--------------------|----------------------|-------------|
| destitute_left     | destitute / low      | 1-5         |
| destitute_right    | destitute / low      | 6-10        |
| lower_middle_left  | lower_middle         | 1-5         |
| lower_middle_right | lower_middle         | 6-10        |
| middle_left        | middle               | 1-5         |
| middle_right       | middle               | 6-10        |
| upper_left         | upper_middle / upper | 1-5         |
| upper_right        | upper_middle / upper | 6-10        |

2. `mix sim.beliefs.init` generates a template graph for each archetype via LLM (8 calls total). Templates are stored as JSON files in `priv/data/belief_templates/`.

3. At seed time, each actor receives the template matching their archetype with deterministic variations:
   - Edge weights adjusted +/-0.15 based on: employment_type, age, has_dollars, receives_welfare
   - Irrelevant edges removed (e.g., an unemployed actor may lose foreign_trade edges)

### Template Storage

```
priv/data/belief_templates/
  destitute_left.json
  destitute_right.json
  lower_middle_left.json
  lower_middle_right.json
  middle_left.json
  middle_right.json
  upper_left.json
  upper_right.json
```

Each file contains a complete graph JSON matching the structure above.

## Simulation Flow

### Updated Flow

```
Actor + Measure + Last Mood + Last Beliefs + History
  → PromptBuilder
  → LLM
  → Decision + New Mood + Belief Deltas
  → Apply deltas to graph → Full snapshot
  → DB (transaction)
```

### Prompt Changes

PromptBuilder adds a new section between emotional state and the new measure:

```
=== TU MODELO MENTAL (como crees que funciona el mundo) ===

Relaciones causales:
- Mas impuestos → menos empleo (peso: -0.7)
- Mas emision → mas inflacion (peso: 0.9)
- Mas planes sociales → menos pobreza (peso: 0.4)

Reacciones emocionales:
- Inflacion → bronca (peso: 0.8)
- Planes sociales → tranquilidad (peso: 0.6)
- Corrupcion → indignacion (peso: 0.9)
```

Edges are sorted by absolute weight (most important first). Prompts remain in Spanish.

### LLM Response Changes

The LLM returns a `belief_update` object with deltas (not the full graph):

```json
{
  "agreement": true,
  "intensity": 7,
  "reasoning": "...",
  "personal_impact": "...",
  "behavior_change": "...",
  "mood_update": { ... },
  "belief_update": {
    "modified_edges": [
      {"from": "taxes", "to": "employment", "type": "causal", "weight": -0.8, "description": "Now I'm more convinced taxes kill jobs"}
    ],
    "new_edges": [
      {"from": "utility_rates", "to": "anger", "type": "emotional", "weight": 0.6, "description": "Rising utility costs are making me angry"}
    ],
    "new_nodes": [
      {"id": "energy_costs", "type": "emergent", "added_at": "Aumento de tarifas"}
    ],
    "removed_edges": [
      {"from": "dollar", "to": "anxiety", "type": "emotional"}
    ]
  }
}
```

### Delta Application Logic

The system applies deltas to the previous graph to produce the new snapshot:

1. Add `new_nodes` to the nodes list
2. For each `modified_edge`: find matching edge by (from, to) and update weight + description
3. Add `new_edges` to the edges list
4. Remove edges matching `removed_edges` by (from, to, type)
5. Clamp all weights to [-1.0, 1.0]
6. Store the resulting full graph as the new ActorBelief snapshot

If `belief_update` is null or missing from the LLM response, the previous graph carries forward unchanged.

## CLI Commands

### Template Generation

```bash
# Generate archetype templates via LLM (8 calls)
mix sim.beliefs.init
```

### Belief Queries

```bash
# Current average beliefs for a population
mix sim.beliefs --population "Panel Fijo"

# Evolution of a specific edge
mix sim.beliefs --population "Panel Fijo" --edge "taxes->employment" --history

# Emergent nodes (which appeared and in how many actors)
mix sim.beliefs --population "Panel Fijo" --emergent
```

### Output Format

```
=== Beliefs: Panel Fijo (100 actors) ===

Top causal beliefs (avg weight):
  inflation -> wages          : -0.82 (std: 0.12)
  taxes -> employment         : -0.65 (std: 0.23)  ** high divergence
  social_welfare -> poverty   : +0.41 (std: 0.31)  ** high divergence

Top emotional reactions:
  corruption -> indignation   : +0.88 (std: 0.08)
  inflation -> anger          : +0.79 (std: 0.15)
  dollar -> anxiety           : +0.71 (std: 0.19)

Emergent nodes (appeared in >10% of actors):
  energy_costs (32 actors) - added after "Aumento de tarifas"
  rent_pressure (18 actors) - added after "Ley de alquileres"
```

## Metrics & Aggregation

### New Aggregator Functions

Uses SQLite `json_extract` and `json_each` for querying within graph JSON:

- **belief_summary(population_id)**: Average weight and std for each edge across the population's latest belief snapshots
- **belief_evolution(population_id)**: Average weight per edge per measure over time
- **emergent_nodes(population_id)**: Count of actors with each emergent node, grouped by the measure that triggered it

### Divergence Detection

Standard deviation of edge weights indicates polarization. Edges with std > 0.25 are flagged as "high divergence" — the population disagrees on that causal/emotional relationship.

## New Files

- `lib/population_simulator/simulation/actor_belief.ex` — Ecto schema + initial graph from archetype
- `lib/population_simulator/simulation/belief_graph.ex` — graph construction, delta application, humanization for prompts
- `lib/mix/tasks/sim.beliefs.init.ex` — generate archetype templates via LLM
- `lib/mix/tasks/sim.beliefs.ex` — query beliefs CLI
- `priv/data/belief_templates/*.json` — 8 archetype template files (generated)
- 1 migration: `create_actor_beliefs`

## Modified Files

- `prompt_builder.ex` — add beliefs section to prompt, request `belief_update` in response JSON
- `claude_client.ex` — parse `belief_update` from response
- `measure_runner.ex` — load latest belief graph, persist new snapshot after delta application
- `sim.seed.ex` — assign initial belief graph from archetype template with variations
- `aggregator.ex` — belief metrics using json_extract
