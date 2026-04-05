# UI Consciousness Update — Design Spec

## Overview

Update the Phoenix LiveView UI to expose the full consciousness system. Three areas of change:

1. **Dashboard** — 6 new sections for population-level consciousness metrics
2. **Cafés page** — New page with chat-style conversation viewer
3. **Actor detail panel** — Enriched with narrative, intenciones, eventos, vínculos, percepciones, disonancia
4. **RunMeasure** — Individual phase checkboxes + multi-phase progress

## Navigation

5 pages total (1 new):
- `/` — Dashboard (expanded)
- `/actors` — Actors directory (actor detail panel enriched)
- `/cafes` — **NEW** Café conversations
- `/run` — Run Measure (updated)
- `/settings` — Settings (unchanged)

Sidebar nav adds "Cafés" link between "Actores" and "Correr Medida".

## Dashboard Expansion

### Existing sections (keep as-is)
- Mood gauges (5 dimensions)
- Mood evolution chart
- Approval bars by measure
- Top beliefs table
- Emergent concepts
- Actor voices

### New sections (add after existing)

#### 1. Disonancia poblacional
- Distribution bar: low (0-0.3) / medium (0.3-0.5) / high (0.5+) with actor counts
- Average dissonance by stratum (horizontal bars)
- Alert badge when >20% of actors have high dissonance
- Query: `decisions` table, latest measure, group by dissonance ranges

#### 2. Eventos activos
- Counter: "X eventos activos en la población"
- Sample of 3-5 recent events with description and actor stratum
- Breakdown: positive vs negative events (based on mood_impact sign)
- Query: `actor_events WHERE active = true`, join actors for stratum

#### 3. Red social (resumen)
- Stats: total bonds formed, average per actor, total with affinity > 0.7
- Top 5 strongest pairs (actor names/strata + shared cafés + affinity)
- Query: `actor_bonds WHERE formed_at IS NOT NULL`, order by affinity desc

#### 4. Percepciones grupales
- Breakdown by zone: "suburbs_outer: 70% frustrados, 30% preocupados"
- Based on group_mood field in actor_perceptions for latest measure
- Query: `actor_perceptions` for latest measure_id, group by zone via actor join

#### 5. Intenciones activas
- Top intentions aggregated: "32 actores: buscar trabajo", "15: comprar dólares"
- Group by similarity (first 30 chars of description)
- Breakdown by stratum
- Query: `actor_intentions WHERE status = 'pending'`, group by description prefix

#### 6. Preview de cafés
- Stats: "X mesas, Y participantes" for latest measure
- 2-3 conversation summaries from different zones
- Link button to /cafes page
- Query: `cafe_sessions` for latest measure_id, sample 3

## Cafés Page (NEW)

### Layout
Split view:
- **Left panel (35%)**: Scrollable list of mesas, filterable
- **Right panel (65%)**: Selected conversation in chat-style bubbles

### Left panel — Mesa selector
- Filter by: measure (dropdown), zone (dropdown)
- Each mesa shows: group_key, participant count, conversation_summary (truncated)
- Selected mesa highlighted with accent border
- Default: select first mesa

### Right panel — Conversation viewer
- Header: group_key, participant count, full conversation_summary
- Messages as chat bubbles:
  - Each actor gets a consistent color (derived from actor_id hash)
  - Name bold above message
  - Alternating left/right alignment based on position
- Below conversation: effects summary
  - Mood deltas per participant (small colored badges)
  - Referents: "María influyó en Jorge: ..."

### Data
- `cafe_sessions` with joined `cafe_effects`
- Conversations stored as JSON in `conversation` field — decode and render
- `participant_names` maps actor_id to fictitious name

### LiveView events
- `select_measure` — filter mesas by measure
- `filter_zone` — filter mesas by zone
- `select_mesa` — load conversation into right panel

## Actor Detail Panel (Enriched)

The existing 500px slide-over panel on ActorsLive gains new sections. Order top to bottom:

### 1. Profile (existing, keep)
Age, stratum, zone, employment, orientation, tenure

### 2. Narrativa autobiográfica (NEW)
- Latest narrative from `actor_summaries` (version indicator)
- Self-observations as bulleted list
- Italic styling, dark card background

### 3. Humor actual (existing, enhanced)
- Keep existing 5 mood bars
- Add: dissonance value from latest decision (colored: green <0.3, yellow 0.3-0.5, red >0.5)

### 4. Intenciones (NEW)
- List pending/resolved intentions from `actor_intentions`
- Pending: 🔄 + description + urgency badge
- Executed: ✅ green
- Frustrated: ❌ red
- Expired: ⏰ gray

### 5. Eventos recientes (NEW)
- Active events from `actor_events WHERE active = true`
- Show description, time ago (duration - remaining), decay indicator
- Max 3

### 6. Vínculos (NEW)
- List bonds from `actor_bonds` where formed_at IS NOT NULL
- Show partner name (from actor profile), shared_cafes count, affinity bar
- Max 10

### 7. Percepción del entorno (NEW)
- Latest perception from `actor_perceptions`
- Group mood label + agreement ratio
- Referent influence text if present

### 8. Decisiones recientes (existing, enhanced)
- Keep existing: title, agreement, intensity, reasoning
- Add: dissonance value per decision (small badge)

## RunMeasure Updates

### Form changes
Add after population selector:
- Checkbox: ☑ Generar eventos personales
- Checkbox: ☑ Correr mesas de café
- Checkbox: ☑ Correr introspección (si es medida #3, 6, 9...)

All checked by default when population is selected.

### Progress changes
Show multi-phase progress:

```
Fase 1: Decisiones ████████████░░░░ 800/1000
Fase 2: Eventos    ████████░░░░░░░░ 120/200  
Fase 3: Cafés      ██░░░░░░░░░░░░░░ 15/143
```

Each phase appears as it starts. Completed phases show green check.

### Completion view
Add to existing completion summary:
- Events generated: X
- Café sessions: X
- Bonds formed: X
- Introspection: X actors (if triggered)

## Data Loading

All new queries use raw SQL via `Ecto.Adapters.SQL.query!` (same pattern as existing Aggregator module). No new Ecto queries in LiveViews — all data access through a new module or extended Aggregator.

### New module: `ConsciousnessAggregator`
Handles all consciousness-related SQL queries for the UI:
- `dissonance_distribution(measure_id)`
- `active_events_summary(population_id)`
- `bonds_summary(population_id)`
- `perceptions_by_zone(measure_id)`
- `active_intentions_summary(population_id)`
- `cafe_preview(measure_id)`
- `actor_consciousness(actor_id)` — loads all consciousness data for one actor

## Modified Files

| File | Change |
|------|--------|
| `router.ex` | Add `/cafes` route |
| `layouts/app.html.heex` | Add "Cafés" nav link |
| `dashboard_live.ex` | Add 6 new sections |
| `actors_live.ex` | Enrich actor detail panel |
| `run_measure_live.ex` | Phase checkboxes + multi-phase progress |

## New Files

| File | Responsibility |
|------|---------------|
| `lib/population_simulator_web/live/cafes_live.ex` | Café conversation page |
| `lib/population_simulator/metrics/consciousness_aggregator.ex` | SQL queries for consciousness UI data |
