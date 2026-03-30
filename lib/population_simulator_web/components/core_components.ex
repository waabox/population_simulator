defmodule PopulationSimulatorWeb.CoreComponents do
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: PopulationSimulatorWeb.Endpoint, router: PopulationSimulatorWeb.Router

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  def nav_link(assigns) do
    ~H"""
    <.link navigate={@href} class={"block px-3 py-2 rounded-md text-sm #{if @active, do: "bg-[#0f3460] text-[#00d2ff]", else: "text-gray-400 hover:text-gray-200 hover:bg-[#0f3460]/50"}"}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :max, :integer, default: 10
  attr :delta, :float, default: nil

  def mood_gauge(assigns) do
    color = cond do
      assigns.value < 4 -> "bg-red-500"
      assigns.value < 7 -> "bg-yellow-500"
      true -> "bg-green-500"
    end
    pct = if assigns.value, do: assigns.value / assigns.max * 100, else: 0
    assigns = assign(assigns, color: color, pct: pct)

    ~H"""
    <div class="bg-[#16213e] rounded-lg p-4">
      <div class="text-xs text-gray-500 uppercase tracking-wider mb-1"><%= @label %></div>
      <div class="flex items-end gap-2">
        <span class="text-2xl font-bold"><%= @value %></span>
        <span class="text-xs text-gray-500 mb-1">/ <%= @max %></span>
        <%= if @delta do %>
          <span class={"text-xs mb-1 #{if @delta > 0, do: "text-green-400", else: "text-red-400"}"}>
            <%= if @delta > 0, do: "+", else: "" %><%= @delta %>
          </span>
        <% end %>
      </div>
      <div class="mt-2 bg-gray-700 rounded-full h-2">
        <div class={"h-2 rounded-full #{@color}"} style={"width: #{@pct}%"}></div>
      </div>
    </div>
    """
  end

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="fixed top-4 right-4 z-50 space-y-2">
      <%= if Phoenix.Flash.get(@flash, :info) do %>
        <div class="bg-[#0f3460] text-[#00d2ff] px-4 py-2 rounded-lg text-sm" phx-click="lv:clear-flash" phx-value-key="info">
          <%= Phoenix.Flash.get(@flash, :info) %>
        </div>
      <% end %>
      <%= if Phoenix.Flash.get(@flash, :error) do %>
        <div class="bg-red-900 text-red-200 px-4 py-2 rounded-lg text-sm" phx-click="lv:clear-flash" phx-value-key="error">
          <%= Phoenix.Flash.get(@flash, :error) %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={"bg-[#16213e] rounded-lg p-4 #{@class}"}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :label, :string, required: true

  def card_title(assigns) do
    ~H"""
    <div class="text-xs text-gray-500 uppercase tracking-wider mb-3"><%= @label %></div>
    """
  end
end
