defmodule PopulationSimulatorWeb.RunMeasureLive do
  use Phoenix.LiveView
  use Phoenix.VerifiedRoutes, router: PopulationSimulatorWeb.Router, endpoint: PopulationSimulatorWeb.Endpoint
  import PopulationSimulatorWeb.CoreComponents

  alias PopulationSimulator.{Repo, Populations.Population, Simulation.Measure, Simulation.MeasureRunner}
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    populations = Repo.all(from p in Population, order_by: [desc: p.inserted_at])
    api_key = Application.get_env(:population_simulator, :claude_api_key) || ""

    {:ok,
     assign(socket,
       active_page: :run,
       api_key_configured?: api_key != "" and api_key != nil,
       populations: populations,
       running: false,
       progress: nil,
       result: nil,
       measure_id: nil
     )}
  end

  @impl true
  def handle_event("run", %{"title" => title, "description" => desc, "population_id" => pop_id}, socket) do
    if desc == "" or pop_id == "" do
      {:noreply, put_flash(socket, :error, "Title, description and population are required")}
    else
      _population = Repo.get!(Population, pop_id)

      {:ok, measure} =
        Repo.insert(Measure.changeset(%Measure{}, %{title: title, description: desc, population_id: pop_id}))

      Phoenix.PubSub.subscribe(PopulationSimulator.PubSub, "simulation:#{measure.id}")

      # Run simulation in a separate process
      me = self()
      Task.start(fn ->
        {:ok, results} = MeasureRunner.run(measure.id, population_id: pop_id)
        send(me, {:simulation_complete, results})
      end)

      {:noreply,
       assign(socket,
         running: true,
         measure_id: measure.id,
         progress: %{ok: 0, error: 0, total: 0, tokens: 0},
         result: nil
       )}
    end
  end

  @impl true
  def handle_info({:simulation_progress, progress}, socket) do
    {:noreply, assign(socket, progress: progress)}
  end

  def handle_info({:simulation_complete, results}, socket) do
    {:noreply, assign(socket, running: false, result: results)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <h2 class="text-xl font-bold mb-6">Run Measure</h2>

      <%= if @result do %>
        <!-- Completion -->
        <.card>
          <div class="text-center py-8">
            <div class="text-2xl font-bold text-green-400 mb-2">Simulation Complete</div>
            <div class="text-gray-400 space-y-1">
              <div><span class="text-gray-200 font-mono"><%= @result.ok %></span> OK | <span class="text-red-400 font-mono"><%= @result.error %></span> errors</div>
              <div><span class="font-mono"><%= format_tokens(@result.tokens) %></span> tokens</div>
            </div>
            <.link navigate={~p"/"} class="inline-block mt-4 bg-[#00d2ff] text-[#1a1a2e] px-4 py-2 rounded-lg text-sm font-semibold hover:bg-[#00b8e6]">
              View Results
            </.link>
          </div>
        </.card>
      <% end %>

      <%= if @running do %>
        <!-- Progress -->
        <.card>
          <.card_title label="Simulation Progress" />
          <div class="mb-4">
            <div class="flex justify-between text-sm mb-1">
              <span><%= @progress.ok + @progress.error %> / <%= @progress.total %> actors</span>
              <span><%= if @progress.total > 0, do: round((@progress.ok + @progress.error) / @progress.total * 100), else: 0 %>%</span>
            </div>
            <div class="bg-gray-700 rounded-full h-3">
              <div class="bg-[#00d2ff] h-3 rounded-full transition-all duration-300"
                style={"width: #{if @progress.total > 0, do: (@progress.ok + @progress.error) / @progress.total * 100, else: 0}%"}></div>
            </div>
          </div>
          <div class="grid grid-cols-3 gap-4 text-center">
            <div>
              <div class="text-xs text-gray-500">OK</div>
              <div class="text-lg font-bold text-green-400"><%= @progress.ok %></div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Errors</div>
              <div class="text-lg font-bold text-red-400"><%= @progress.error %></div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Tokens</div>
              <div class="text-lg font-bold"><%= format_tokens(@progress.tokens) %></div>
            </div>
          </div>
        </.card>
      <% end %>

      <%= if not @running and @result == nil do %>
        <!-- Form -->
        <form phx-submit="run" class="space-y-4">
          <div>
            <label class="block text-sm text-gray-400 mb-1">Title</label>
            <input type="text" name="title" required
              class="w-full bg-[#16213e] border border-gray-600 rounded-lg px-3 py-2 text-sm text-gray-200 focus:outline-none focus:border-[#00d2ff]" />
          </div>
          <div>
            <label class="block text-sm text-gray-400 mb-1">Description</label>
            <textarea name="description" rows="4" required
              class="w-full bg-[#16213e] border border-gray-600 rounded-lg px-3 py-2 text-sm text-gray-200 focus:outline-none focus:border-[#00d2ff]"></textarea>
          </div>
          <div>
            <label class="block text-sm text-gray-400 mb-1">Population</label>
            <select name="population_id" required class="w-full bg-[#16213e] border border-gray-600 rounded-lg px-3 py-2 text-sm text-gray-200">
              <option value="">Select...</option>
              <%= for pop <- @populations do %>
                <option value={pop.id}><%= pop.name %></option>
              <% end %>
            </select>
          </div>
          <button type="submit" disabled={not @api_key_configured?}
            class={"w-full py-2 rounded-lg text-sm font-semibold #{if @api_key_configured?, do: "bg-[#e94560] text-white hover:bg-[#d63851] cursor-pointer", else: "bg-gray-700 text-gray-500 cursor-not-allowed"}"}>
            <%= if @api_key_configured?, do: "Run Simulation", else: "Configure API Key in Settings first" %>
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp format_tokens(n) when n > 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_tokens(n) when n > 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_tokens(n), do: "#{n}"
end
