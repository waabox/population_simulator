defmodule PopulationSimulatorWeb.ActorsLive do
  use Phoenix.LiveView
  import PopulationSimulatorWeb.CoreComponents

  alias PopulationSimulator.{Repo, Populations.Population}
  import Ecto.Query

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    populations = Repo.all(from p in Population, order_by: [desc: p.inserted_at])
    api_key = Application.get_env(:population_simulator, :claude_api_key) || ""

    {:ok,
     assign(socket,
       active_page: :actors,
       api_key_configured?: api_key != "" and api_key != nil,
       populations: populations,
       selected_population: List.first(populations),
       view_mode: :table,
       page: 0,
       actors: [],
       total_actors: 0,
       filters: %{stratum: nil, zone: nil, employment: nil, age_min: nil, age_max: nil},
       selected_actor: nil,
       per_page: @per_page
     )
     |> load_actors()}
  end

  @impl true
  def handle_event("select_population", %{"id" => id}, socket) do
    population = Enum.find(socket.assigns.populations, &(&1.id == id))
    {:noreply, socket |> assign(selected_population: population, page: 0) |> load_actors()}
  end

  def handle_event("toggle_view", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, view_mode: String.to_existing_atom(mode))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(page: String.to_integer(page)) |> load_actors()}
  end

  def handle_event("filter", params, socket) do
    filters = %{
      stratum: blank_to_nil(params["stratum"]),
      zone: blank_to_nil(params["zone"]),
      employment: blank_to_nil(params["employment"]),
      age_min: parse_int(params["age_min"]),
      age_max: parse_int(params["age_max"])
    }

    {:noreply, socket |> assign(filters: filters, page: 0) |> load_actors()}
  end

  def handle_event("select_actor", %{"id" => id}, socket) do
    actor_detail = load_actor_detail(id)
    {:noreply, assign(socket, selected_actor: actor_detail)}
  end

  def handle_event("close_actor", _, socket) do
    {:noreply, assign(socket, selected_actor: nil)}
  end

  defp load_actors(%{assigns: %{selected_population: nil}} = socket), do: assign(socket, actors: [], total_actors: 0)

  defp load_actors(socket) do
    %{selected_population: pop, page: page, filters: filters} = socket.assigns
    offset = page * @per_page

    {where_clause, params} = build_where(filters, pop.id)

    %{rows: [[total]]} = Repo.query!("SELECT COUNT(*) FROM actors a JOIN actor_populations ap ON ap.actor_id = a.id #{where_clause}", params)

    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT a.id, a.age, a.stratum, a.zone, a.employment_type, a.political_orientation,
               m.economic_confidence, m.government_trust, m.personal_wellbeing, m.social_anger, m.future_outlook,
               m.narrative
        FROM actors a
        JOIN actor_populations ap ON ap.actor_id = a.id
        LEFT JOIN actor_moods m ON m.actor_id = a.id
          AND m.inserted_at = (SELECT MAX(inserted_at) FROM actor_moods WHERE actor_id = a.id)
        #{where_clause}
        ORDER BY a.age
        LIMIT ?#{length(params) + 1} OFFSET ?#{length(params) + 2}
        """,
        params ++ [to_string(@per_page), to_string(offset)]
      )

    actors = Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)

    assign(socket, actors: actors, total_actors: total)
  end

  defp build_where(filters, population_id) do
    conditions = ["ap.population_id = ?1"]
    params = [population_id]
    idx = 2

    {conditions, params, idx} = if filters.stratum do
      {conditions ++ ["a.stratum = ?#{idx}"], params ++ [filters.stratum], idx + 1}
    else
      {conditions, params, idx}
    end

    {conditions, params, idx} = if filters.zone do
      {conditions ++ ["a.zone = ?#{idx}"], params ++ [filters.zone], idx + 1}
    else
      {conditions, params, idx}
    end

    {conditions, params, idx} = if filters.employment do
      {conditions ++ ["a.employment_type = ?#{idx}"], params ++ [filters.employment], idx + 1}
    else
      {conditions, params, idx}
    end

    {conditions, params, idx} = if filters.age_min do
      {conditions ++ ["a.age >= ?#{idx}"], params ++ [to_string(filters.age_min)], idx + 1}
    else
      {conditions, params, idx}
    end

    {conditions, params, _idx} = if filters.age_max do
      {conditions ++ ["a.age <= ?#{idx}"], params ++ [to_string(filters.age_max)], idx + 1}
    else
      {conditions, params, idx}
    end

    {"WHERE " <> Enum.join(conditions, " AND "), params}
  end

  defp load_actor_detail(actor_id) do
    %{rows: [row]} =
      Repo.query!(
        "SELECT a.id, a.age, a.stratum, a.zone, a.employment_type, a.political_orientation, a.tenure, a.profile FROM actors a WHERE a.id = ?1",
        [actor_id]
      )

    [id, age, stratum, zone, employment, orientation, tenure, profile] = row

    %{rows: mood_rows} =
      Repo.query!(
        """
        SELECT m.economic_confidence, m.government_trust, m.personal_wellbeing, m.social_anger, m.future_outlook, m.narrative, ms.title
        FROM actor_moods m
        LEFT JOIN measures ms ON ms.id = m.measure_id
        WHERE m.actor_id = ?1
        ORDER BY m.inserted_at
        """,
        [actor_id]
      )

    %{rows: decision_rows} =
      Repo.query!(
        """
        SELECT ms.title, d.agreement, d.intensity, d.reasoning, d.personal_impact
        FROM decisions d
        JOIN measures ms ON ms.id = d.measure_id
        WHERE d.actor_id = ?1
        ORDER BY d.inserted_at
        """,
        [actor_id]
      )

    %{
      id: id, age: age, stratum: stratum, zone: zone, employment: employment,
      orientation: orientation, tenure: tenure, profile: profile,
      moods: Enum.map(mood_rows, fn [ec, gt, pw, sa, fo, narr, title] ->
        %{econ: ec, trust: gt, well: pw, anger: sa, future: fo, narrative: narr, measure: title}
      end),
      decisions: Enum.map(decision_rows, fn [title, agreement, intensity, reasoning, impact] ->
        %{title: title, agreement: agreement == 1, intensity: intensity, reasoning: reasoning, impact: impact}
      end)
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(v), do: v

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative">
      <!-- Population pills -->
      <div class="flex gap-2 mb-4 flex-wrap">
        <%= for pop <- @populations do %>
          <button phx-click="select_population" phx-value-id={pop.id}
            class={"px-3 py-1.5 rounded-full text-sm #{if @selected_population && @selected_population.id == pop.id, do: "bg-[#0f3460] text-[#00d2ff] ring-1 ring-[#00d2ff]", else: "bg-[#16213e] text-gray-400 hover:text-gray-200"}"}>
            <%= pop.name %>
          </button>
        <% end %>
      </div>

      <!-- Filters + view toggle -->
      <div class="flex justify-between items-end mb-4">
        <form phx-change="filter" class="flex gap-2 items-end">
          <select name="stratum" class="bg-[#16213e] border border-gray-600 rounded px-2 py-1 text-xs text-gray-300">
            <option value="">All strata</option>
            <%= for s <- ~w(destitute low lower_middle middle upper_middle upper) do %>
              <option value={s} selected={@filters.stratum == s}><%= s %></option>
            <% end %>
          </select>
          <select name="zone" class="bg-[#16213e] border border-gray-600 rounded px-2 py-1 text-xs text-gray-300">
            <option value="">All zones</option>
            <%= for z <- ~w(caba_north caba_south suburbs_inner suburbs_middle suburbs_outer) do %>
              <option value={z} selected={@filters.zone == z}><%= z %></option>
            <% end %>
          </select>
          <select name="employment" class="bg-[#16213e] border border-gray-600 rounded px-2 py-1 text-xs text-gray-300">
            <option value="">All employment</option>
            <%= for e <- ~w(formal_employee informal_employee self_employed employer unemployed inactive) do %>
              <option value={e} selected={@filters.employment == e}><%= e %></option>
            <% end %>
          </select>
          <input type="number" name="age_min" placeholder="Age min" value={@filters.age_min} class="bg-[#16213e] border border-gray-600 rounded px-2 py-1 text-xs text-gray-300 w-20" />
          <input type="number" name="age_max" placeholder="Age max" value={@filters.age_max} class="bg-[#16213e] border border-gray-600 rounded px-2 py-1 text-xs text-gray-300 w-20" />
        </form>
        <div class="flex gap-1">
          <button phx-click="toggle_view" phx-value-mode="table" class={"px-2 py-1 rounded text-xs #{if @view_mode == :table, do: "bg-[#0f3460] text-[#00d2ff]", else: "text-gray-500 hover:text-gray-300"}"}>Table</button>
          <button phx-click="toggle_view" phx-value-mode="grid" class={"px-2 py-1 rounded text-xs #{if @view_mode == :grid, do: "bg-[#0f3460] text-[#00d2ff]", else: "text-gray-500 hover:text-gray-300"}"}>Grid</button>
        </div>
      </div>

      <!-- Table view -->
      <%= if @view_mode == :table do %>
        <div class="bg-[#16213e] rounded-lg overflow-hidden">
          <table class="w-full text-xs">
            <thead>
              <tr class="border-b border-gray-700">
                <th class="px-3 py-2 text-left text-gray-500">Age</th>
                <th class="px-3 py-2 text-left text-gray-500">Stratum</th>
                <th class="px-3 py-2 text-left text-gray-500">Zone</th>
                <th class="px-3 py-2 text-left text-gray-500">Employment</th>
                <th class="px-3 py-2 text-left text-gray-500">Pol</th>
                <th class="px-3 py-2 text-left text-gray-500">Econ</th>
                <th class="px-3 py-2 text-left text-gray-500">Trust</th>
                <th class="px-3 py-2 text-left text-gray-500">Well</th>
                <th class="px-3 py-2 text-left text-gray-500">Anger</th>
                <th class="px-3 py-2 text-left text-gray-500">Future</th>
              </tr>
            </thead>
            <tbody>
              <%= for actor <- @actors do %>
                <tr class="border-b border-gray-700/50 hover:bg-[#0f3460]/30 cursor-pointer" phx-click="select_actor" phx-value-id={actor["id"]}>
                  <td class="px-3 py-2"><%= actor["age"] %></td>
                  <td class="px-3 py-2"><%= actor["stratum"] %></td>
                  <td class="px-3 py-2"><%= actor["zone"] %></td>
                  <td class="px-3 py-2"><%= actor["employment_type"] %></td>
                  <td class="px-3 py-2"><%= actor["political_orientation"] %></td>
                  <td class="px-3 py-2"><%= mood_cell(actor["economic_confidence"]) %></td>
                  <td class="px-3 py-2"><%= mood_cell(actor["government_trust"]) %></td>
                  <td class="px-3 py-2"><%= mood_cell(actor["personal_wellbeing"]) %></td>
                  <td class="px-3 py-2"><%= mood_cell(actor["social_anger"]) %></td>
                  <td class="px-3 py-2"><%= mood_cell(actor["future_outlook"]) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% else %>
        <!-- Grid view -->
        <div class="grid grid-cols-4 gap-3">
          <%= for actor <- @actors do %>
            <div class="bg-[#16213e] rounded-lg p-3 cursor-pointer hover:ring-1 hover:ring-[#00d2ff]/50" phx-click="select_actor" phx-value-id={actor["id"]}>
              <div class="text-xs text-gray-400 mb-2"><%= actor["age"] %>yo | <%= actor["stratum"] %> | <%= actor["zone"] %></div>
              <div class="flex gap-1 mb-2">
                <div class={"h-1.5 rounded-full flex-1 #{mood_color(actor["economic_confidence"])}"} title="Econ"></div>
                <div class={"h-1.5 rounded-full flex-1 #{mood_color(actor["government_trust"])}"} title="Trust"></div>
                <div class={"h-1.5 rounded-full flex-1 #{mood_color(actor["personal_wellbeing"])}"} title="Well"></div>
                <div class={"h-1.5 rounded-full flex-1 #{mood_color(actor["social_anger"])}"} title="Anger"></div>
                <div class={"h-1.5 rounded-full flex-1 #{mood_color(actor["future_outlook"])}"} title="Future"></div>
              </div>
              <div class="text-xs text-gray-500 italic line-clamp-2"><%= String.slice(actor["narrative"] || "No narrative", 0, 100) %></div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Pagination -->
      <div class="flex justify-between items-center mt-4 text-xs text-gray-500">
        <span><%= @total_actors %> actors</span>
        <div class="flex gap-2">
          <%= if @page > 0 do %>
            <button phx-click="page" phx-value-page={@page - 1} class="text-[#00d2ff] hover:underline">Previous</button>
          <% end %>
          <span>Page <%= @page + 1 %> of <%= max(div(@total_actors + @per_page - 1, @per_page), 1) %></span>
          <%= if (@page + 1) * @per_page < @total_actors do %>
            <button phx-click="page" phx-value-page={@page + 1} class="text-[#00d2ff] hover:underline">Next</button>
          <% end %>
        </div>
      </div>

      <!-- Actor detail slide-over -->
      <%= if @selected_actor do %>
        <div class="fixed inset-0 z-40 bg-black/50" phx-click="close_actor"></div>
        <div class="fixed right-0 top-0 bottom-0 w-[500px] z-50 bg-[#1a1a2e] border-l border-gray-700 overflow-y-auto p-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg font-bold">Actor Detail</h3>
            <button phx-click="close_actor" class="text-gray-500 hover:text-gray-300 text-xl">&times;</button>
          </div>

          <div class="space-y-4 text-xs">
            <!-- Profile -->
            <.card>
              <.card_title label="Profile" />
              <div class="grid grid-cols-2 gap-1 text-gray-400">
                <div>Age: <span class="text-gray-200"><%= @selected_actor.age %></span></div>
                <div>Stratum: <span class="text-gray-200"><%= @selected_actor.stratum %></span></div>
                <div>Zone: <span class="text-gray-200"><%= @selected_actor.zone %></span></div>
                <div>Employment: <span class="text-gray-200"><%= @selected_actor.employment %></span></div>
                <div>Orientation: <span class="text-gray-200"><%= @selected_actor.orientation %>/10</span></div>
                <div>Tenure: <span class="text-gray-200"><%= @selected_actor.tenure %></span></div>
              </div>
            </.card>

            <!-- Current mood -->
            <%= if @selected_actor.moods != [] do %>
              <% current = List.last(@selected_actor.moods) %>
              <.card>
                <.card_title label="Current Mood" />
                <div class="space-y-1">
                  <%= for {label, val} <- [{"Econ", current.econ}, {"Trust", current.trust}, {"Well", current.well}, {"Anger", current.anger}, {"Future", current.future}] do %>
                    <div class="flex items-center gap-2">
                      <span class="w-12 text-gray-500"><%= label %></span>
                      <div class="flex-1 bg-gray-700 rounded-full h-1.5">
                        <div class={"h-1.5 rounded-full #{mood_color(val)}"} style={"width: #{(val || 0) * 10}%"}></div>
                      </div>
                      <span class="w-6 text-right"><%= val %></span>
                    </div>
                  <% end %>
                </div>
                <%= if current.narrative do %>
                  <p class="mt-2 text-gray-400 italic">"<%= current.narrative %>"</p>
                <% end %>
              </.card>
            <% end %>

            <!-- Decisions -->
            <.card>
              <.card_title label="Decision History" />
              <div class="space-y-2">
                <%= for d <- @selected_actor.decisions do %>
                  <div class="border-b border-gray-700/50 pb-2">
                    <div class="flex items-center gap-2">
                      <span class={"w-4 h-4 rounded-full text-center text-[10px] leading-4 #{if d.agreement, do: "bg-green-900 text-green-300", else: "bg-red-900 text-red-300"}"}><%= if d.agreement, do: "✓", else: "✗" %></span>
                      <span class="text-gray-300 font-medium"><%= d.title %></span>
                      <span class="text-gray-500">intensity: <%= d.intensity %>/10</span>
                    </div>
                    <p class="text-gray-500 mt-1"><%= d.reasoning %></p>
                  </div>
                <% end %>
                <%= if @selected_actor.decisions == [] do %>
                  <p class="text-gray-600">No decisions yet.</p>
                <% end %>
              </div>
            </.card>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp mood_cell(nil), do: "-"
  defp mood_cell(val), do: val

  defp mood_color(nil), do: "bg-gray-600"
  defp mood_color(val) when val < 4, do: "bg-red-500"
  defp mood_color(val) when val < 7, do: "bg-yellow-500"
  defp mood_color(_), do: "bg-green-500"

  defp per_page, do: @per_page
end
