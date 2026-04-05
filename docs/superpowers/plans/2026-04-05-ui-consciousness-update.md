# UI Consciousness Update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the Phoenix LiveView UI to expose the full consciousness system: 6 new dashboard sections, a chat-style cafés page, enriched actor detail panel, and multi-phase simulation runner.

**Architecture:** A new `ConsciousnessAggregator` module provides all SQL queries for consciousness data. Dashboard, ActorsLive, and RunMeasureLive are extended with new sections. A new CafesLive page shows conversations in chat-style. All follow existing patterns (raw SQL via `Ecto.Adapters.SQL.query!`, PubSub for async progress).

**Tech Stack:** Elixir, Phoenix LiveView, Tailwind CSS, SQLite3, existing component system (`.card`, `.mood_gauge`, `.nav_link`).

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `lib/population_simulator/metrics/consciousness_aggregator.ex` | All consciousness SQL queries for UI |
| `lib/population_simulator_web/live/cafes_live.ex` | Café conversations page with chat-style viewer |

### Modified files

| File | Change |
|------|--------|
| `lib/population_simulator_web/router.ex` | Add `/cafes` route |
| `lib/population_simulator_web/components/layouts/app.html.heex` | Add "Cafés" nav link |
| `lib/population_simulator_web/live/dashboard_live.ex` | Add 6 consciousness sections |
| `lib/population_simulator_web/live/actors_live.ex` | Enrich actor detail panel |
| `lib/population_simulator_web/live/run_measure_live.ex` | Phase checkboxes + multi-phase progress |

---

## Task 1: ConsciousnessAggregator

**Files:**
- Create: `lib/population_simulator/metrics/consciousness_aggregator.ex`

- [ ] **Step 1: Create ConsciousnessAggregator with all queries**

```elixir
# lib/population_simulator/metrics/consciousness_aggregator.ex
defmodule PopulationSimulator.Metrics.ConsciousnessAggregator do
  @moduledoc """
  SQL queries for consciousness UI data: dissonance, events, bonds,
  perceptions, intentions, café previews, and per-actor consciousness.
  """

  alias PopulationSimulator.Repo

  def dissonance_distribution(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT
          CASE
            WHEN d.dissonance < 0.3 THEN 'low'
            WHEN d.dissonance < 0.5 THEN 'medium'
            ELSE 'high'
          END as level,
          COUNT(*) as cnt
        FROM decisions d
        JOIN actor_populations ap ON ap.actor_id = d.actor_id
        WHERE ap.population_id = ?1
          AND d.dissonance IS NOT NULL
          AND d.measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
        GROUP BY level
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def dissonance_by_stratum(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT json_extract(a.profile, '$.stratum') as stratum,
               ROUND(AVG(d.dissonance), 3) as avg_dissonance,
               COUNT(*) as cnt
        FROM decisions d
        JOIN actors a ON a.id = d.actor_id
        JOIN actor_populations ap ON ap.actor_id = d.actor_id
        WHERE ap.population_id = ?1
          AND d.dissonance IS NOT NULL
          AND d.measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
        GROUP BY stratum
        ORDER BY avg_dissonance DESC
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def active_events_summary(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT e.description,
               json_extract(a.profile, '$.stratum') as stratum,
               e.duration, e.remaining,
               json_extract(e.mood_impact, '$.economic_confidence') as econ_impact,
               json_extract(e.mood_impact, '$.social_anger') as anger_impact
        FROM actor_events e
        JOIN actors a ON a.id = e.actor_id
        JOIN actor_populations ap ON ap.actor_id = e.actor_id
        WHERE ap.population_id = ?1 AND e.active = 1
        ORDER BY e.inserted_at DESC
        LIMIT 20
      """, [population_id])

    events = Enum.map(rows, fn row -> to_map(cols, row) end)
    total = length(events)
    negative = Enum.count(events, fn e -> (e["econ_impact"] || 0) < 0 or (e["anger_impact"] || 0) > 0 end)

    %{events: Enum.take(events, 5), total: total, negative: negative, positive: total - negative}
  end

  def bonds_summary(population_id) do
    %{rows: [[total, avg_affinity, formed_count]]} =
      Repo.query!("""
        SELECT COUNT(*) as total,
               ROUND(AVG(b.affinity), 2) as avg_affinity,
               SUM(CASE WHEN b.formed_at IS NOT NULL THEN 1 ELSE 0 END) as formed
        FROM actor_bonds b
        WHERE b.actor_a_id IN (SELECT actor_id FROM actor_populations WHERE population_id = ?1)
      """, [population_id])

    %{columns: top_cols, rows: top_rows} =
      Repo.query!("""
        SELECT
          json_extract(a1.profile, '$.stratum') || ' (' || a1.age || ')' as actor_a,
          json_extract(a2.profile, '$.stratum') || ' (' || a2.age || ')' as actor_b,
          b.shared_cafes, ROUND(b.affinity, 2) as affinity
        FROM actor_bonds b
        JOIN actors a1 ON a1.id = b.actor_a_id
        JOIN actors a2 ON a2.id = b.actor_b_id
        WHERE b.formed_at IS NOT NULL
          AND b.actor_a_id IN (SELECT actor_id FROM actor_populations WHERE population_id = ?1)
        ORDER BY b.affinity DESC
        LIMIT 5
      """, [population_id])

    %{
      total: total || 0,
      avg_affinity: avg_affinity || 0,
      formed: formed_count || 0,
      top_pairs: Enum.map(top_rows, fn row -> to_map(top_cols, row) end)
    }
  end

  def perceptions_by_zone(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT a.zone,
               p.group_mood,
               COUNT(*) as cnt
        FROM actor_perceptions p
        JOIN actors a ON a.id = p.actor_id
        JOIN actor_populations ap ON ap.actor_id = p.actor_id
        WHERE ap.population_id = ?1
          AND p.measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
        GROUP BY a.zone, p.group_mood
        ORDER BY a.zone
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def active_intentions_summary(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT SUBSTR(i.description, 1, 50) as intent,
               json_extract(a.profile, '$.stratum') as stratum,
               i.urgency,
               COUNT(*) as cnt
        FROM actor_intentions i
        JOIN actors a ON a.id = i.actor_id
        JOIN actor_populations ap ON ap.actor_id = i.actor_id
        WHERE ap.population_id = ?1 AND i.status = 'pending'
        GROUP BY SUBSTR(i.description, 1, 30), stratum
        ORDER BY cnt DESC
        LIMIT 15
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def cafe_preview(population_id) do
    %{rows: [[count]]} =
      Repo.query!("""
        SELECT COUNT(*)
        FROM cafe_sessions cs
        WHERE cs.measure_id = (
          SELECT m.id FROM measures m
          WHERE m.population_id = ?1
          ORDER BY m.inserted_at DESC LIMIT 1
        )
      """, [population_id])

    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT cs.group_key, cs.conversation_summary
        FROM cafe_sessions cs
        WHERE cs.measure_id = (
          SELECT m.id FROM measures m
          WHERE m.population_id = ?1
          ORDER BY m.inserted_at DESC LIMIT 1
        )
        ORDER BY RANDOM()
        LIMIT 3
      """, [population_id])

    %{
      total_mesas: count || 0,
      samples: Enum.map(rows, fn row -> to_map(cols, row) end)
    }
  end

  def actor_consciousness(actor_id) do
    narrative = load_actor_narrative(actor_id)
    intentions = load_actor_intentions(actor_id)
    events = load_actor_events(actor_id)
    bonds = load_actor_bonds(actor_id)
    perception = load_actor_perception(actor_id)
    dissonance = load_actor_dissonance(actor_id)

    %{
      narrative: narrative,
      intentions: intentions,
      events: events,
      bonds: bonds,
      perception: perception,
      dissonance: dissonance
    }
  end

  defp load_actor_narrative(actor_id) do
    case Repo.query!("SELECT narrative, self_observations, version FROM actor_summaries WHERE actor_id = ?1 ORDER BY version DESC LIMIT 1", [actor_id]) do
      %{rows: [[narrative, observations, version]]} ->
        %{narrative: narrative, observations: Jason.decode!(observations || "[]"), version: version}
      _ -> nil
    end
  end

  defp load_actor_intentions(actor_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT description, urgency, status, inserted_at
        FROM actor_intentions
        WHERE actor_id = ?1
        ORDER BY inserted_at DESC
        LIMIT 5
      """, [actor_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  defp load_actor_events(actor_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT description, duration, remaining, active, inserted_at
        FROM actor_events
        WHERE actor_id = ?1
        ORDER BY inserted_at DESC
        LIMIT 5
      """, [actor_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  defp load_actor_bonds(actor_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT
          CASE WHEN b.actor_a_id = ?1 THEN b.actor_b_id ELSE b.actor_a_id END as partner_id,
          CASE WHEN b.actor_a_id = ?1
            THEN json_extract(a2.profile, '$.stratum') || ' (' || a2.age || ', ' || a2.zone || ')'
            ELSE json_extract(a1.profile, '$.stratum') || ' (' || a1.age || ', ' || a1.zone || ')'
          END as partner_desc,
          b.shared_cafes, ROUND(b.affinity, 2) as affinity
        FROM actor_bonds b
        JOIN actors a1 ON a1.id = b.actor_a_id
        JOIN actors a2 ON a2.id = b.actor_b_id
        WHERE (b.actor_a_id = ?1 OR b.actor_b_id = ?1) AND b.formed_at IS NOT NULL
        ORDER BY b.affinity DESC
        LIMIT 10
      """, [actor_id, actor_id, actor_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  defp load_actor_perception(actor_id) do
    case Repo.query!("""
      SELECT p.group_mood, p.referent_influence
      FROM actor_perceptions p
      WHERE p.actor_id = ?1
      ORDER BY p.inserted_at DESC
      LIMIT 1
    """, [actor_id]) do
      %{rows: [[group_mood, referent_influence]]} ->
        %{group_mood: Jason.decode!(group_mood || "{}"), referent_influence: referent_influence}
      _ -> nil
    end
  end

  defp load_actor_dissonance(actor_id) do
    case Repo.query!("""
      SELECT dissonance FROM decisions
      WHERE actor_id = ?1 AND dissonance IS NOT NULL
      ORDER BY inserted_at DESC LIMIT 1
    """, [actor_id]) do
      %{rows: [[val]]} -> val
      _ -> nil
    end
  end

  defp to_map(columns, row) do
    columns |> Enum.zip(row) |> Map.new()
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/metrics/consciousness_aggregator.ex
git commit -m "Add ConsciousnessAggregator with all consciousness SQL queries for UI"
```

---

## Task 2: Router + Layout (navigation)

**Files:**
- Modify: `lib/population_simulator_web/router.ex`
- Modify: `lib/population_simulator_web/components/layouts/app.html.heex`

- [ ] **Step 1: Add /cafes route**

Read `router.ex`. Add after the `/actors` route:

```elixir
      live "/cafes", CafesLive, :index
```

- [ ] **Step 2: Add nav link in layout**

Read `app.html.heex`. Find the nav links section. After the "Actores" nav_link, add:

```heex
        <.nav_link href="/cafes" icon="chat-bubble-left-right" label="Cafés" active={@active_page == :cafes} />
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Warning about CafesLive not existing yet — that's fine.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator_web/router.ex lib/population_simulator_web/components/layouts/app.html.heex
git commit -m "Add /cafes route and nav link"
```

---

## Task 3: Dashboard expansion (6 new sections)

**Files:**
- Modify: `lib/population_simulator_web/live/dashboard_live.ex`

- [ ] **Step 1: Read the current dashboard_live.ex completely**

Understand the existing `load_dashboard_data/2`, `mount/3`, and `render/1` structure.

- [ ] **Step 2: Add ConsciousnessAggregator alias and new assigns**

Add alias:
```elixir
alias PopulationSimulator.Metrics.ConsciousnessAggregator
```

In `mount/3`, add new assigns:
```elixir
    dissonance: nil,
    dissonance_by_stratum: [],
    events_summary: nil,
    bonds_summary: nil,
    perceptions: [],
    intentions: [],
    cafe_preview: nil,
```

- [ ] **Step 3: Load consciousness data in load_dashboard_data/2**

After the existing data loading (mood, beliefs, etc.), add:

```elixir
    dissonance = ConsciousnessAggregator.dissonance_distribution(population.id)
    dissonance_strat = ConsciousnessAggregator.dissonance_by_stratum(population.id)
    events_summary = ConsciousnessAggregator.active_events_summary(population.id)
    bonds_summary = ConsciousnessAggregator.bonds_summary(population.id)
    perceptions = ConsciousnessAggregator.perceptions_by_zone(population.id)
    intentions = ConsciousnessAggregator.active_intentions_summary(population.id)
    cafe_preview = ConsciousnessAggregator.cafe_preview(population.id)
```

And assign them all to the socket.

- [ ] **Step 4: Add render sections for each new consciousness block**

After the existing sections in `render/1`, add 6 new `.card` sections. Each section follows the same pattern as existing ones — a `.card` with a `.card_title` and content. Use the existing CSS/component classes.

**Dissonance section:** 3 colored bars (green/yellow/red) showing low/medium/high counts. Below, a list of strata with avg dissonance.

**Events section:** Counter header "X eventos activos". List of 5 recent events with description and stratum. Positive/negative breakdown.

**Bonds section:** Stats line "X vínculos formados, afinidad promedio: X". Table of top 5 pairs.

**Perceptions section:** By zone, show mood label and agreement %. 

**Intentions section:** List of top intentions with count and stratum badges.

**Café preview section:** "X mesas en el último café". 2-3 conversation summaries. Link button to /cafes.

Each section should be wrapped in:
```heex
<.card :if={@selected_population}>
  <.card_title>Sección Title</.card_title>
  <!-- content -->
</.card>
```

- [ ] **Step 5: Verify compilation and test in browser**

Run: `mix compile`
Open `http://localhost:4000` and verify sections appear when a population is selected.

- [ ] **Step 6: Commit**

```bash
git add lib/population_simulator_web/live/dashboard_live.ex
git commit -m "Add 6 consciousness sections to dashboard"
```

---

## Task 4: CafesLive page

**Files:**
- Create: `lib/population_simulator_web/live/cafes_live.ex`

- [ ] **Step 1: Create CafesLive with chat-style conversation viewer**

```elixir
# lib/population_simulator_web/live/cafes_live.ex
defmodule PopulationSimulatorWeb.CafesLive do
  use Phoenix.LiveView
  import PopulationSimulatorWeb.CoreComponents

  alias PopulationSimulator.{Repo, Populations.Population}
  import Ecto.Query

  @colors ["#00d2ff", "#e94560", "#4ade80", "#fbbf24", "#a78bfa", "#f472b6", "#34d399", "#fb923c", "#818cf8", "#f87171", "#2dd4bf", "#facc15"]

  def mount(_params, _session, socket) do
    populations = Repo.all(from(p in Population, order_by: [asc: p.inserted_at]))
    api_key = Application.get_env(:population_simulator, :claude_api_key)

    {:ok,
     assign(socket,
       active_page: :cafes,
       api_key_configured?: api_key != nil and api_key != "",
       populations: populations,
       selected_population: List.first(populations),
       measures: [],
       selected_measure: nil,
       zone_filter: nil,
       mesas: [],
       selected_mesa: nil,
       conversation: [],
       names: %{},
       effects: [],
       summary: ""
     )
     |> then(fn s ->
       if s.assigns.selected_population do
         load_measures(s, s.assigns.selected_population)
       else
         s
       end
     end)}
  end

  def handle_event("select_population", %{"id" => id}, socket) do
    population = Enum.find(socket.assigns.populations, &(&1.id == id))
    {:noreply, socket |> assign(selected_population: population) |> load_measures(population)}
  end

  def handle_event("select_measure", %{"id" => id}, socket) do
    {:noreply, socket |> assign(selected_measure: id, zone_filter: nil) |> load_mesas()}
  end

  def handle_event("filter_zone", %{"zone" => zone}, socket) do
    zone = if zone == "", do: nil, else: zone
    {:noreply, socket |> assign(zone_filter: zone) |> load_mesas()}
  end

  def handle_event("select_mesa", %{"id" => id}, socket) do
    {:noreply, load_conversation(socket, id)}
  end

  defp load_measures(socket, population) do
    %{rows: rows} =
      Repo.query!("""
        SELECT DISTINCT m.id, m.title, m.inserted_at
        FROM measures m
        JOIN cafe_sessions cs ON cs.measure_id = m.id
        WHERE m.population_id = ?1
        ORDER BY m.inserted_at DESC
      """, [population.id])

    measures = Enum.map(rows, fn [id, title, ts] -> %{id: id, title: title, inserted_at: ts} end)
    selected = List.first(measures)

    socket
    |> assign(measures: measures, selected_measure: selected && selected.id)
    |> load_mesas()
  end

  defp load_mesas(socket) do
    measure_id = socket.assigns.selected_measure
    zone = socket.assigns.zone_filter

    if measure_id do
      query = """
        SELECT cs.id, cs.group_key, cs.conversation_summary, cs.participant_ids
        FROM cafe_sessions cs
        WHERE cs.measure_id = ?1
        #{if zone, do: "AND cs.group_key LIKE ?2", else: ""}
        ORDER BY cs.group_key
      """
      params = if zone, do: [measure_id, "#{zone}%"], else: [measure_id]

      %{rows: rows} = Repo.query!(query, params)

      mesas = Enum.map(rows, fn [id, key, summary, participants] ->
        participant_count = length(Jason.decode!(participants))
        %{id: id, group_key: key, summary: summary, participant_count: participant_count}
      end)

      socket = assign(socket, mesas: mesas)

      if mesas != [] do
        load_conversation(socket, List.first(mesas).id)
      else
        assign(socket, selected_mesa: nil, conversation: [], names: %{}, effects: [], summary: "")
      end
    else
      assign(socket, mesas: [], selected_mesa: nil, conversation: [], names: %{}, effects: [], summary: "")
    end
  end

  defp load_conversation(socket, mesa_id) do
    %{rows: [[conversation_json, names_json, summary, _effects_json]]} =
      Repo.query!("""
        SELECT cs.conversation, cs.participant_names, cs.conversation_summary, cs.participant_ids
        FROM cafe_sessions cs
        WHERE cs.id = ?1
      """, [mesa_id])

    conversation = Jason.decode!(conversation_json)
    names = Jason.decode!(names_json)

    # Load effects
    %{columns: cols, rows: effect_rows} =
      Repo.query!("""
        SELECT ce.actor_id, ce.mood_deltas
        FROM cafe_effects ce
        WHERE ce.cafe_session_id = ?1
      """, [mesa_id])

    effects = Enum.map(effect_rows, fn row ->
      map = Enum.zip(cols, row) |> Map.new()
      Map.put(map, "mood_deltas", Jason.decode!(map["mood_deltas"]))
    end)

    assign(socket,
      selected_mesa: mesa_id,
      conversation: conversation,
      names: names,
      effects: effects,
      summary: summary
    )
  end

  defp color_for_actor(actor_id) do
    index = :erlang.phash2(actor_id, length(@colors))
    Enum.at(@colors, index)
  end

  def render(assigns) do
    ~H"""
    <div class="flex gap-6 h-[calc(100vh-120px)]">
      <!-- Left: Mesa selector -->
      <div class="w-[35%] flex flex-col gap-3 overflow-hidden">
        <!-- Population pills -->
        <div class="flex flex-wrap gap-2">
          <button :for={pop <- @populations}
            phx-click="select_population" phx-value-id={pop.id}
            class={"px-3 py-1 rounded-full text-sm #{if @selected_population && @selected_population.id == pop.id, do: "bg-[#00d2ff] text-black", else: "bg-[#16213e] text-gray-300 hover:bg-[#1a1a4e]"}"}>
            <%= pop.name %>
          </button>
        </div>

        <!-- Measure selector -->
        <select phx-change="select_measure" class="bg-[#16213e] text-gray-300 rounded px-3 py-2 text-sm border border-gray-700">
          <option :for={m <- @measures} value={m.id} selected={m.id == @selected_measure}>
            <%= m.title %>
          </option>
        </select>

        <!-- Zone filter -->
        <select phx-change="filter_zone" name="zone" class="bg-[#16213e] text-gray-300 rounded px-3 py-2 text-sm border border-gray-700">
          <option value="">Todas las zonas</option>
          <option value="caba_north">CABA Norte</option>
          <option value="caba_south">CABA Sur</option>
          <option value="suburbs_inner">Suburbs Inner</option>
          <option value="suburbs_middle">Suburbs Middle</option>
          <option value="suburbs_outer">Suburbs Outer</option>
        </select>

        <!-- Mesa list -->
        <div class="flex-1 overflow-y-auto space-y-1">
          <div :for={mesa <- @mesas}
            phx-click="select_mesa" phx-value-id={mesa.id}
            class={"p-3 rounded cursor-pointer text-sm #{if @selected_mesa == mesa.id, do: "bg-[#16213e] border-l-2 border-[#00d2ff]", else: "bg-[#1a1a2e] hover:bg-[#16213e]"}"}>
            <div class="font-medium text-gray-200"><%= mesa.group_key %></div>
            <div class="text-gray-500 text-xs mt-1"><%= mesa.participant_count %> personas</div>
            <div class="text-gray-400 text-xs mt-1 line-clamp-2"><%= mesa.summary %></div>
          </div>
          <div :if={@mesas == []} class="text-gray-500 text-sm p-4">
            No hay cafés para esta medida/zona.
          </div>
        </div>
      </div>

      <!-- Right: Conversation -->
      <div class="w-[65%] flex flex-col bg-[#0f0f23] rounded-lg overflow-hidden">
        <div :if={@selected_mesa} class="flex flex-col h-full">
          <!-- Header -->
          <div class="p-4 border-b border-gray-800">
            <div class="text-gray-400 text-xs mb-1">CONVERSACIÓN</div>
            <div class="text-gray-200 text-sm"><%= @summary %></div>
          </div>

          <!-- Messages -->
          <div class="flex-1 overflow-y-auto p-4 space-y-3">
            <div :for={{msg, idx} <- Enum.with_index(@conversation)}>
              <div class={"max-w-[85%] #{if rem(idx, 2) == 0, do: "", else: "ml-auto"}"}>
                <div class="text-xs font-bold mb-1" style={"color: #{color_for_actor(msg["actor_id"])}"}>
                  <%= msg["name"] %>
                </div>
                <div class={"p-3 rounded-xl text-sm text-gray-200 #{if rem(idx, 2) == 0, do: "bg-[#16213e]", else: "bg-[#2d1b3d]"}"}>
                  <%= msg["message"] %>
                </div>
              </div>
            </div>
          </div>

          <!-- Effects -->
          <div :if={@effects != []} class="p-3 border-t border-gray-800 text-xs">
            <div class="text-gray-500 mb-2">EFECTOS EN HUMOR</div>
            <div class="flex flex-wrap gap-2">
              <div :for={effect <- @effects} class="flex items-center gap-1">
                <span style={"color: #{color_for_actor(effect["actor_id"])}"}>
                  <%= Map.get(@names, effect["actor_id"], "?") %>:
                </span>
                <span :for={{dim, val} <- effect["mood_deltas"]}
                  class={"#{if val > 0, do: "text-green-400", else: "text-red-400"}"}>
                  <%= dim |> String.slice(0..3) %><%= if val > 0, do: "+#{val}", else: val %>
                </span>
              </div>
            </div>
          </div>
        </div>

        <div :if={!@selected_mesa} class="flex items-center justify-center h-full text-gray-500">
          Seleccioná una mesa para ver la conversación
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean.

- [ ] **Step 3: Test in browser**

Run: `mix phx.server`
Navigate to `http://localhost:4000/cafes`. Verify the page loads with mesa list and conversations.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator_web/live/cafes_live.ex
git commit -m "Add CafesLive with chat-style conversation viewer"
```

---

## Task 5: Actor detail panel enrichment

**Files:**
- Modify: `lib/population_simulator_web/live/actors_live.ex`

- [ ] **Step 1: Read actors_live.ex completely**

Focus on `load_actor_detail/1` and the render section for the side panel.

- [ ] **Step 2: Add consciousness data to load_actor_detail**

Add alias:
```elixir
alias PopulationSimulator.Metrics.ConsciousnessAggregator
```

In `load_actor_detail/1`, after the existing profile/mood/decision loading, add:

```elixir
    consciousness = ConsciousnessAggregator.actor_consciousness(actor_id)
```

Include `consciousness` in the returned map.

- [ ] **Step 3: Add consciousness sections to actor detail panel render**

In the render function, find the actor detail side panel (the fixed-position overlay). After the existing sections (profile, mood, decisions), add new sections matching the mockup:

**Narrativa:** Dark card with italic text, version badge, self-observations as bullet list.

**Intenciones:** List with status icons (🔄 pending, ✅ executed, ❌ frustrated, ⏰ expired) and urgency badge.

**Eventos:** Active events with description, time-ago indicator, decay status.

**Vínculos:** Partner description, shared cafés, affinity bar (width proportional to 0-1).

**Percepción:** Group mood label, agreement %, referent influence text.

**Disonancia:** Small colored badge on the mood section (green <0.3, yellow 0.3-0.5, red >0.5).

Also enhance the existing decisions section: add dissonance badge per decision.

- [ ] **Step 4: Verify compilation and test**

Run: `mix compile && mix phx.server`
Click on an actor in `/actors`, verify the enriched panel shows all sections.

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator_web/live/actors_live.ex
git commit -m "Enrich actor detail panel with consciousness data"
```

---

## Task 6: RunMeasure phase checkboxes + progress

**Files:**
- Modify: `lib/population_simulator_web/live/run_measure_live.ex`

- [ ] **Step 1: Read run_measure_live.ex completely**

Focus on the form, the async task, and progress handling.

- [ ] **Step 2: Add phase checkboxes to form**

After the population selector in the form, add 3 checkboxes:

```heex
<div class="space-y-2 mt-4">
  <label class="flex items-center gap-2 text-sm text-gray-300">
    <input type="checkbox" name="events" value="true" checked class="rounded bg-[#16213e] border-gray-600" />
    Generar eventos personales
  </label>
  <label class="flex items-center gap-2 text-sm text-gray-300">
    <input type="checkbox" name="cafe" value="true" checked class="rounded bg-[#16213e] border-gray-600" />
    Correr mesas de café
  </label>
  <label class="flex items-center gap-2 text-sm text-gray-300">
    <input type="checkbox" name="introspection" value="true" class="rounded bg-[#16213e] border-gray-600" />
    Correr introspección
  </label>
</div>
```

- [ ] **Step 3: Update the async task to run phases**

In the `handle_event("run", ...)` callback, after `MeasureRunner.run` completes, check the phase checkboxes and run additional phases:

```elixir
    # After MeasureRunner.run completes in the spawned task:
    if params["events"] == "true" do
      Phoenix.PubSub.broadcast(PopulationSimulator.PubSub, topic, {:phase_start, "events"})
      event_results = PopulationSimulator.Simulation.EventGenerator.run(measure, actors, concurrency: concurrency)
      Phoenix.PubSub.broadcast(PopulationSimulator.PubSub, topic, {:phase_complete, "events", event_results})
    end

    if params["cafe"] == "true" do
      Phoenix.PubSub.broadcast(PopulationSimulator.PubSub, topic, {:phase_start, "cafe"})
      decisions = Repo.all(from(d in Decision, where: d.measure_id == ^measure.id))
      cafe_results = PopulationSimulator.Simulation.CafeRunner.run(measure, actors, decisions, concurrency: concurrency)
      Phoenix.PubSub.broadcast(PopulationSimulator.PubSub, topic, {:phase_complete, "cafe", cafe_results})
    end

    if params["introspection"] == "true" do
      Phoenix.PubSub.broadcast(PopulationSimulator.PubSub, topic, {:phase_start, "introspection"})
      intro_results = PopulationSimulator.Simulation.IntrospectionRunner.run(measure, actors, concurrency: concurrency)
      Phoenix.PubSub.broadcast(PopulationSimulator.PubSub, topic, {:phase_complete, "introspection", intro_results})
    end
```

- [ ] **Step 4: Add multi-phase progress display**

Add new assigns:
```elixir
    current_phase: "decisions",
    phase_results: %{}
```

Handle new PubSub messages:
```elixir
  def handle_info({:phase_start, phase}, socket) do
    {:noreply, assign(socket, current_phase: phase)}
  end

  def handle_info({:phase_complete, phase, results}, socket) do
    phase_results = Map.put(socket.assigns.phase_results, phase, results)
    {:noreply, assign(socket, phase_results: phase_results)}
  end
```

In the progress render section, show phases:
```heex
<div :if={@running} class="space-y-2">
  <div :for={phase <- ["decisions", "events", "cafe", "introspection"]}>
    <div class="flex items-center gap-2 text-sm">
      <span :if={Map.has_key?(@phase_results, phase)} class="text-green-400">✓</span>
      <span :if={@current_phase == phase && !Map.has_key?(@phase_results, phase)} class="text-yellow-400 animate-pulse">●</span>
      <span :if={@current_phase != phase && !Map.has_key?(@phase_results, phase)} class="text-gray-600">○</span>
      <span class="text-gray-300 capitalize"><%= phase %></span>
      <span :if={Map.has_key?(@phase_results, phase)} class="text-gray-500 text-xs">
        <%= Map.get(@phase_results[phase], :ok, 0) %> OK
      </span>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Update completion view**

Add phase results to the completion summary.

- [ ] **Step 6: Verify compilation and test**

Run: `mix compile && mix phx.server`
Navigate to `/run`, verify checkboxes appear and phases show during simulation.

- [ ] **Step 7: Commit**

```bash
git add lib/population_simulator_web/live/run_measure_live.ex
git commit -m "Add phase checkboxes and multi-phase progress to RunMeasure"
```

---

## Task 7: CLAUDE.md + final cleanup

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Document UI updates**

Add to CLAUDE.md in the appropriate sections:

In Key design decisions:
```markdown
- **UI**: Phoenix LiveView dashboard with 5 pages. Dashboard shows mood, beliefs, approval, dissonance, events, bonds, perceptions, intentions, and café previews. CafesLive page has chat-style conversation viewer with mesa selector. ActorsLive detail panel shows full consciousness state per actor. RunMeasureLive supports per-phase checkboxes (events, café, introspection).
```

In Core Modules:
```markdown
| `ConsciousnessAggregator` | SQL queries for consciousness UI: dissonance, events, bonds, perceptions, intentions |
```

- [ ] **Step 2: Commit and push**

```bash
git add CLAUDE.md
git commit -m "Document UI consciousness features in CLAUDE.md"
git push
```
