# Web Dashboard — Design Spec

## Context

The population simulator has a rich CLI for running simulations and querying results (`sim.dashboard`, `sim.mood`, `sim.beliefs`, etc.). This spec adds a Phoenix LiveView web dashboard that provides a visual interface for all existing functionality plus real-time simulation progress.

## Stack

- Phoenix 1.7+ with LiveView
- Tailwind CSS for styling
- Chart.js via LiveView hooks for charts
- Phoenix.PubSub for real-time simulation progress
- No additional database changes — all queries use existing tables

## Architecture

### New Files

```
lib/population_simulator_web/
  router.ex
  endpoint.ex
  components/
    layouts.ex                       # Root + app layout (sidebar)
    core_components.ex               # Shared UI components (mood bars, badges, etc.)
  live/
    dashboard_live.ex                # Main dashboard (mood gauges + charts + beliefs)
    actors_live.ex                   # Actor list with table/grid toggle
    actor_detail_component.ex        # Slide-over panel for actor detail
    run_measure_live.ex              # Measure form + live progress
    settings_live.ex                 # API key + model config
assets/
  css/app.css                        # Tailwind styles
  js/app.js                          # LiveView JS + Chart.js hooks
```

### Modified Files

- `mix.exs` — add phoenix, phoenix_live_view, phoenix_html, tailwind, esbuild, heroicons
- `config/config.exs` — phoenix endpoint config
- `config/dev.exs` — dev server config (port 4000, watchers)
- `lib/population_simulator/application.ex` — add Endpoint to supervision tree
- `lib/population_simulator/simulation/measure_runner.ex` — emit PubSub events every 10 actors

## Pages

### Sidebar (always visible)

Fixed left sidebar, dark background:

- **Header**: "Population Simulator" title
- **Populations section**:
  - List of populations (clickeable, selected one highlighted)
  - "+" button that reveals inline form (name + description + create button)
  - Each population shows name and actor count
- **Navigation**:
  - Dashboard (icon + text)
  - Actors (icon + text)
  - Run Measure (icon + text)
  - Settings (icon + text)
- **API key indicator**: green dot if configured, red dot if not

Selected population is stored in the LiveView session and persists across page navigation. All pages that show population data use this selection.

### Dashboard

Visible when a population is selected. Shows all data via SQL queries (no LLM calls).

**Row 1 — Mood Gauges (5 cards in a row)**

| Card | Value | Visual |
|------|-------|--------|
| Economic Confidence | 1.7/10 | Progress bar, colored red/yellow/green based on value. Delta from previous measure shown as badge (e.g., "-0.3") |
| Government Trust | 1.4/10 | Same format |
| Personal Wellbeing | 1.9/10 | Same format |
| Social Anger | 9.4/10 | Same format |
| Future Outlook | 1.8/10 | Same format |

Color thresholds: red < 4, yellow 4-6, green > 6.

**Row 2 — Two large cards**

- **Mood Evolution** (left, 60% width): Line chart (Chart.js). X-axis = measures (chronological). Y-axis = 1-10. One line per mood dimension (5 lines, color-coded). Tooltip on hover shows exact values.
- **Approval by Measure** (right, 40% width): Horizontal bar chart. One bar per measure with approval % and intensity labeled.

**Row 3 — Three cards**

- **Top Beliefs**: Table of top 10 edges. Columns: Edge (from → to), Type (C/E badge), Avg Weight, Actors. Sorted by absolute weight descending.
- **Emergent Concepts**: List of emergent nodes with actor count. Sorted by frequency. Each shows the node ID and how many actors have it.
- **Actor Voices**: 3 random actor narratives. Each shows: profile summary (age, stratum, zone, employment, pol), mood values, and the narrative text in italics. "Refresh" button to load 3 new random actors.

**Empty state**: When no population is selected, shows centered message: "Select a population from the sidebar or create one."

### Actors

Toggle between table and grid views via button in top-right corner.

**Filters bar (top)**:
- Stratum dropdown (multi-select)
- Zone dropdown (multi-select)
- Employment type dropdown (multi-select)
- Age range (min/max inputs)
- Search by actor ID (text input)

**Table view**:
- Columns: Age, Sex, Stratum, Zone, Employment, Pol. Orientation, Mood (5 mini progress bars inline), Last Decision (agree/disagree icon + intensity)
- Paginated: 50 per page
- Sortable by any column (click header)
- Click on row opens actor detail panel

**Grid view**:
- Cards showing: age + stratum + zone header, 5 mood mini-bars with colors, political orientation as colored badge, last narrative truncated to 2 lines
- Same pagination and filters as table
- Click on card opens actor detail panel

**Actor detail (slide-over panel)**:

Opens from the right side when clicking an actor. Contains:

1. **Profile section**: All demographic data (age, sex, zone, education, employment, sector, income, housing, household size, financial profile)
2. **Current mood**: 5 dimensions with colored progress bars
3. **Mood history**: Small line chart showing this actor's mood evolution across measures
4. **Decision history**: List of all decisions. Each shows: measure title, agreement (green check / red X), intensity bar, reasoning text, personal_impact
5. **Belief graph**: List of current edges sorted by absolute weight. Each shows: from → to, type badge (C/E), weight as colored bar (-1 to +1), description text
6. **Current narrative**: Full text of the actor's latest mood narrative

Close button (X) in top-right of panel.

### Run Measure

**Form state**:
- Title: text input (required)
- Description: textarea, 4 rows (required)
- Population: dropdown pre-filled with sidebar selection (required)
- "Run Simulation" button: red/prominent. Disabled with tooltip if no API key configured.

**Progress state** (replaces form when running):

The form is replaced by a progress view:

1. **Progress bar**: "347/1000 actors (34.7%) — ~180s remaining". Bar fills left to right. Percentage and ETA update in real-time.
2. **Live indicators** (4 small cards below the bar):
   - Approval %: updates every 10 actors
   - Avg Mood (social anger as headline): updates every 10 actors
   - Errors: count of failed actor evaluations
   - Tokens: total consumed so far
3. **Completion state**: "Simulation complete! 982 OK, 18 errors, 2.1M tokens, 262s". Button "View Results" navigates to Dashboard.

**Implementation**: MeasureRunner emits `Phoenix.PubSub.broadcast` on topic `"simulation:#{measure_id}"` every 10 actors with `%{ok: count, error: count, total: total, tokens: tokens, partial_approval: pct, partial_anger: avg}`. The LiveView subscribes to this topic when simulation starts.

### Settings

Simple form:

- **API Key**: password input with show/hide toggle button. Stored in `Application.put_env(:population_simulator, :claude_api_key, value)` at runtime. Does not persist across restarts.
- **Model**: dropdown select. Options: `claude-haiku-4-5-20251001`, `claude-sonnet-4-5-20250514`. Stored in Application env.
- "Save" button. Success flash message on save.

Note: Since the API key is stored in runtime memory only, the Settings page shows a warning: "API key is stored in memory and will be lost when the server restarts."

## MeasureRunner PubSub Integration

### Changes to measure_runner.ex

The `run/2` function is modified minimally:

1. Accept an optional `measure_id` in the existing opts for PubSub topic
2. Add a counter (using `:counters`) incremented in each `evaluate_actor` callback
3. Every 10 successful actors, broadcast partial results to `"simulation:#{measure_id}"`

The broadcast payload:

```elixir
%{
  ok: ok_count,
  error: error_count,
  total: total_actors,
  tokens: total_tokens,
  partial_approval: approval_percentage,
  partial_anger: avg_social_anger
}
```

Partial metrics are computed from the decisions/moods already persisted — a simple COUNT/AVG query on the decisions table filtered by measure_id.

## Queries

All dashboard queries reuse the same SQL patterns from `Metrics.Aggregator` and `Mix.Tasks.Sim.Dashboard`. No new query logic needed — the LiveViews call the existing Aggregator functions and add a few simple Ecto queries for actor listing/detail.

New queries needed only for:
- Actor list with pagination: `from(a in Actor, join: ap in ActorPopulation, ..., limit: 50, offset: page * 50)`
- Actor detail: load actor + latest mood + latest belief + all decisions for that actor
- Partial metrics during simulation: quick COUNT/AVG on decisions for a specific measure_id

## Dark Theme

The entire UI uses a dark theme consistent with the mockup:
- Background: `#1a1a2e` (deep navy)
- Cards: `#16213e` (lighter navy)
- Accent: `#00d2ff` (cyan for highlights, selected items)
- Danger/negative: `#e94560` (red for low mood values, alerts)
- Success/positive: `#10b981` (green for high mood, agreement)
- Text: `#e0e0e0` (light gray)
- Secondary text: `#888888`
