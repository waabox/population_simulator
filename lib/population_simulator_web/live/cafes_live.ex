# lib/population_simulator_web/live/cafes_live.ex
defmodule PopulationSimulatorWeb.CafesLive do
  use Phoenix.LiveView

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
