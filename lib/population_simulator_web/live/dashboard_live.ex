defmodule PopulationSimulatorWeb.DashboardLive do
  use Phoenix.LiveView
  import PopulationSimulatorWeb.CoreComponents

  alias PopulationSimulator.{Repo, Populations.Population, Metrics.Aggregator}
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    populations = Repo.all(from p in Population, order_by: [desc: p.inserted_at])

    api_key = Application.get_env(:population_simulator, :claude_api_key) || ""

    {:ok,
     assign(socket,
       active_page: :dashboard,
       api_key_configured?: api_key != "" and api_key != nil,
       populations: populations,
       selected_population: nil,
       mood: nil,
       mood_evolution: [],
       approval: [],
       beliefs: [],
       emergent: [],
       voices: [],
       mood_deltas: %{}
     )}
  end

  @impl true
  def handle_event("select_population", %{"id" => id}, socket) do
    population = Enum.find(socket.assigns.populations, &(&1.id == id))
    socket = load_dashboard_data(socket, population)
    {:noreply, socket}
  end

  def handle_event("refresh_voices", _, socket) do
    if socket.assigns.selected_population do
      voices = load_voices(socket.assigns.selected_population.id)
      {:noreply, assign(socket, voices: voices)}
    else
      {:noreply, socket}
    end
  end

  defp load_dashboard_data(socket, nil), do: assign(socket, selected_population: nil)

  defp load_dashboard_data(socket, population) do
    mood = Aggregator.mood_summary(population.id)
    mood_evolution = Aggregator.mood_evolution(population.id)
    beliefs = load_top_beliefs(population.id)
    emergent = load_emergent(population.id)
    voices = load_voices(population.id)
    approval = load_approval(population.id)

    mood_deltas = calculate_deltas(mood, mood_evolution)

    assign(socket,
      selected_population: population,
      mood: mood,
      mood_evolution: mood_evolution,
      beliefs: beliefs,
      emergent: emergent,
      voices: voices,
      approval: approval,
      mood_deltas: mood_deltas
    )
  end

  defp calculate_deltas(_mood, []), do: %{}
  defp calculate_deltas(_mood, evolution) when length(evolution) < 2, do: %{}

  defp calculate_deltas(_mood, evolution) do
    [prev, current] = Enum.take(evolution, -2)

    %{
      "economic_confidence" => safe_delta(current["economic_confidence"], prev["economic_confidence"]),
      "government_trust" => safe_delta(current["government_trust"], prev["government_trust"]),
      "personal_wellbeing" => safe_delta(current["personal_wellbeing"], prev["personal_wellbeing"]),
      "social_anger" => safe_delta(current["social_anger"], prev["social_anger"]),
      "future_outlook" => safe_delta(current["future_outlook"], prev["future_outlook"])
    }
  end

  defp safe_delta(nil, _), do: nil
  defp safe_delta(_, nil), do: nil
  defp safe_delta(a, b), do: Float.round(a - b, 1)

  defp load_top_beliefs(population_id) do
    Aggregator.belief_summary(population_id) |> Enum.take(10)
  end

  defp load_emergent(population_id) do
    Aggregator.emergent_nodes(population_id) |> Enum.take(10)
  end

  defp load_approval(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          ms.title,
          COUNT(*) as total,
          ROUND(100.0 * SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as pct,
          ROUND(AVG(d.intensity), 1) as intensity
        FROM decisions d
        JOIN measures ms ON ms.id = d.measure_id
        JOIN actor_populations ap ON ap.actor_id = d.actor_id
        WHERE ap.population_id = ?1
        GROUP BY d.measure_id, ms.title
        ORDER BY MIN(d.inserted_at)
        """,
        [population_id]
      )

    Enum.map(rows, fn [title, total, pct, intensity] ->
      %{title: title, total: total, pct: pct, intensity: intensity}
    end)
  end

  defp load_voices(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT a.age, a.stratum, a.zone, a.employment_type, a.political_orientation,
               m.economic_confidence, m.government_trust, m.personal_wellbeing,
               m.social_anger, m.future_outlook, m.narrative
        FROM actor_moods m
        JOIN (SELECT actor_id, MAX(inserted_at) as max_ts FROM actor_moods GROUP BY actor_id) latest
          ON latest.actor_id = m.actor_id AND latest.max_ts = m.inserted_at
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        JOIN actors a ON a.id = m.actor_id
        WHERE ap.population_id = ?1 AND m.narrative IS NOT NULL AND m.narrative != ''
        ORDER BY RANDOM() LIMIT 3
        """,
        [population_id]
      )

    Enum.map(rows, fn [age, stratum, zone, employment, orientation, econ, trust, well, anger, future, narrative] ->
      %{
        profile: "#{age}yo | #{stratum} | #{zone} | #{employment} | pol:#{orientation}",
        mood: "econ:#{econ} trust:#{trust} well:#{well} anger:#{anger} future:#{future}",
        narrative: narrative
      }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Population selector pills -->
      <div class="flex gap-2 mb-6 flex-wrap">
        <%= for pop <- @populations do %>
          <button
            phx-click="select_population"
            phx-value-id={pop.id}
            class={"px-3 py-1.5 rounded-full text-sm #{if @selected_population && @selected_population.id == pop.id, do: "bg-[#0f3460] text-[#00d2ff] ring-1 ring-[#00d2ff]", else: "bg-[#16213e] text-gray-400 hover:text-gray-200"}"}
          >
            <%= pop.name %>
          </button>
        <% end %>
      </div>

      <%= if @selected_population do %>
        <!-- Mood Gauges -->
        <div class="grid grid-cols-5 gap-4 mb-6">
          <.mood_gauge label="Economic Confidence" value={@mood["economic_confidence"]} delta={@mood_deltas["economic_confidence"]} />
          <.mood_gauge label="Government Trust" value={@mood["government_trust"]} delta={@mood_deltas["government_trust"]} />
          <.mood_gauge label="Personal Wellbeing" value={@mood["personal_wellbeing"]} delta={@mood_deltas["personal_wellbeing"]} />
          <.mood_gauge label="Social Anger" value={@mood["social_anger"]} delta={@mood_deltas["social_anger"]} />
          <.mood_gauge label="Future Outlook" value={@mood["future_outlook"]} delta={@mood_deltas["future_outlook"]} />
        </div>

        <!-- Charts row -->
        <div class="grid grid-cols-5 gap-4 mb-6">
          <.card class="col-span-3">
            <.card_title label="Mood Evolution" />
            <canvas id="mood-chart" phx-hook="Chart" data-chart={mood_chart_config(@mood_evolution)} class="w-full" height="200"></canvas>
          </.card>
          <.card class="col-span-2">
            <.card_title label="Approval by Measure" />
            <%= for entry <- @approval do %>
              <div class="mb-2">
                <div class="flex justify-between text-xs mb-1">
                  <span class="text-gray-400 truncate max-w-[200px]"><%= entry.title %></span>
                  <span><%= entry.pct %>%</span>
                </div>
                <div class="bg-gray-700 rounded-full h-2">
                  <div class="bg-[#00d2ff] h-2 rounded-full" style={"width: #{entry.pct}%"}></div>
                </div>
              </div>
            <% end %>
          </.card>
        </div>

        <!-- Bottom row -->
        <div class="grid grid-cols-3 gap-4">
          <.card>
            <.card_title label="Top Beliefs" />
            <div class="space-y-1 text-xs">
              <%= for b <- @beliefs do %>
                <div class="flex justify-between">
                  <span class="text-gray-400">
                    <span class={"px-1 rounded #{if b["type"] == "causal", do: "bg-blue-900 text-blue-300", else: "bg-purple-900 text-purple-300"}"}><%= if b["type"] == "causal", do: "C", else: "E" %></span>
                    <%= b["from"] %> → <%= b["to"] %>
                  </span>
                  <span class="font-mono"><%= format_weight(b["avg_weight"]) %></span>
                </div>
              <% end %>
            </div>
          </.card>

          <.card>
            <.card_title label="Emergent Concepts" />
            <div class="space-y-1 text-xs">
              <%= for n <- @emergent do %>
                <div class="flex justify-between">
                  <span class="text-gray-400"><%= n["node_id"] %></span>
                  <span><%= n["actor_count"] %> actors</span>
                </div>
              <% end %>
              <%= if @emergent == [] do %>
                <p class="text-gray-600">No emergent concepts yet.</p>
              <% end %>
            </div>
          </.card>

          <.card>
            <div class="flex justify-between items-center mb-3">
              <.card_title label="Actor Voices" />
              <button phx-click="refresh_voices" class="text-xs text-[#00d2ff] hover:underline">Refresh</button>
            </div>
            <div class="space-y-3">
              <%= for v <- @voices do %>
                <div class="text-xs">
                  <div class="text-gray-500"><%= v.profile %></div>
                  <div class="text-gray-400 italic mt-1">"<%= String.slice(v.narrative || "", 0, 150) %>"</div>
                </div>
              <% end %>
              <%= if @voices == [] do %>
                <p class="text-gray-600 text-xs">No actor narratives yet. Run a measure first.</p>
              <% end %>
            </div>
          </.card>
        </div>
      <% else %>
        <div class="flex items-center justify-center h-96">
          <p class="text-gray-500 text-lg">Select a population to view the dashboard.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp mood_chart_config(evolution) do
    labels = Enum.map(evolution, & &1["measure"])
    datasets = [
      %{label: "Econ. Confidence", data: Enum.map(evolution, & &1["economic_confidence"]), borderColor: "#00d2ff", tension: 0.3},
      %{label: "Gov. Trust", data: Enum.map(evolution, & &1["government_trust"]), borderColor: "#10b981", tension: 0.3},
      %{label: "Wellbeing", data: Enum.map(evolution, & &1["personal_wellbeing"]), borderColor: "#f59e0b", tension: 0.3},
      %{label: "Anger", data: Enum.map(evolution, & &1["social_anger"]), borderColor: "#e94560", tension: 0.3},
      %{label: "Future", data: Enum.map(evolution, & &1["future_outlook"]), borderColor: "#8b5cf6", tension: 0.3}
    ]

    Jason.encode!(%{
      type: "line",
      data: %{labels: labels, datasets: datasets},
      options: %{
        responsive: true,
        scales: %{y: %{min: 0, max: 10, grid: %{color: "rgba(255,255,255,0.05)"}}, x: %{grid: %{color: "rgba(255,255,255,0.05)"}, ticks: %{maxRotation: 45}}},
        plugins: %{legend: %{labels: %{color: "#888", boxWidth: 12, font: %{size: 10}}}}
      }
    })
  end

  defp format_weight(nil), do: "-"
  defp format_weight(w) when w >= 0, do: "+#{w}"
  defp format_weight(w), do: "#{w}"
end
