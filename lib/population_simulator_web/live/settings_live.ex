defmodule PopulationSimulatorWeb.SettingsLive do
  use Phoenix.LiveView

  @models [
    {"claude-haiku-4-5-20251001", "Claude Haiku 4.5"},
    {"claude-sonnet-4-5-20250514", "Claude Sonnet 4.5"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    current_key = Application.get_env(:population_simulator, :claude_api_key) || ""
    current_model = Application.get_env(:population_simulator, :claude_model, "claude-haiku-4-5-20251001")

    {:ok,
     assign(socket,
       active_page: :settings,
       api_key_configured?: current_key != "" and current_key != nil,
       api_key: current_key,
       model: current_model,
       models: @models,
       show_key: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg">
      <h2 class="text-xl font-bold mb-6">Settings</h2>

      <form phx-submit="save" class="space-y-6">
        <div>
          <label class="block text-sm text-gray-400 mb-1">API Key</label>
          <div class="flex gap-2">
            <input
              type={if @show_key, do: "text", else: "password"}
              name="api_key"
              value={@api_key}
              placeholder="sk-ant-..."
              class="flex-1 bg-[#0f3460] border border-gray-600 rounded-lg px-3 py-2 text-sm text-gray-200 focus:outline-none focus:border-[#00d2ff]"
            />
            <button type="button" phx-click="toggle_key" class="px-3 py-2 bg-[#0f3460] rounded-lg text-sm text-gray-400 hover:text-gray-200">
              <%= if @show_key, do: "Hide", else: "Show" %>
            </button>
          </div>
          <p class="text-xs text-gray-600 mt-1">Stored in memory only. Lost on server restart.</p>
        </div>

        <div>
          <label class="block text-sm text-gray-400 mb-1">Model</label>
          <select name="model" class="w-full bg-[#0f3460] border border-gray-600 rounded-lg px-3 py-2 text-sm text-gray-200 focus:outline-none focus:border-[#00d2ff]">
            <%= for {id, name} <- @models do %>
              <option value={id} selected={id == @model}><%= name %></option>
            <% end %>
          </select>
        </div>

        <button type="submit" class="bg-[#00d2ff] text-[#1a1a2e] px-4 py-2 rounded-lg text-sm font-semibold hover:bg-[#00b8e6]">
          Save
        </button>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"api_key" => key, "model" => model}, socket) do
    Application.put_env(:population_simulator, :claude_api_key, key)
    Application.put_env(:population_simulator, :claude_model, model)

    {:noreply,
     socket
     |> assign(api_key: key, model: model, api_key_configured?: key != "")
     |> put_flash(:info, "Settings saved")}
  end

  def handle_event("toggle_key", _, socket) do
    {:noreply, assign(socket, show_key: !socket.assigns.show_key)}
  end
end
