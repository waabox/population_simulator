# Web Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Phoenix LiveView web dashboard for visualizing populations, running simulations with live progress, and exploring individual actors.

**Architecture:** Phoenix 1.7+ with LiveView added to the existing Elixir project. Sidebar layout with 4 pages (Dashboard, Actors, Run Measure, Settings). Chart.js via JS hooks for line/bar charts. PubSub for real-time simulation progress. Dark theme with Tailwind CSS. All data from existing SQLite queries.

**Tech Stack:** Phoenix 1.7+, LiveView 1.0+, Tailwind CSS, Chart.js, Phoenix.PubSub, esbuild

---

### Task 1: Add Phoenix dependencies and boilerplate config

**Files:**
- Modify: `mix.exs`
- Modify: `config/config.exs`
- Modify: `config/dev.exs`
- Modify: `config/runtime.exs`
- Modify: `lib/population_simulator/application.ex`

- [ ] **Step 1: Update mix.exs with Phoenix dependencies**

Add to deps in `mix.exs`:

```elixir
  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.17"},
      {:req, "~> 0.5"},
      {:nimble_csv, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:faker, "~> 0.18", only: [:dev, :test]},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.1.1", sparse: "optimized", app: false, compile: false, depth: 1},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:plug_cowboy, "~> 2.7"}
    ]
  end
```

Also add to `project/0`:

```elixir
  def project do
    [
      app: :population_simulator,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      compilers: Mix.compilers()
    ]
  end
```

And update aliases:

```elixir
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind population_simulator", "esbuild population_simulator"],
      "assets.deploy": ["tailwind population_simulator --minify", "esbuild population_simulator --minify", "phx.digest"]
    ]
  end
```

- [ ] **Step 2: Update config/config.exs**

Replace with:

```elixir
import Config

config :population_simulator,
  ecto_repos: [PopulationSimulator.Repo]

config :population_simulator, PopulationSimulator.Repo,
  database: Path.expand("../population_simulator_dev.db", __DIR__),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :population_simulator, PopulationSimulatorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PopulationSimulatorWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: PopulationSimulator.PubSub,
  live_view: [signing_salt: "population_sim_salt"]

config :esbuild,
  version: "0.17.11",
  population_simulator: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  population_simulator: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
```

- [ ] **Step 3: Update config/dev.exs**

```elixir
import Config

config :population_simulator, PopulationSimulatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_to_accept_it_ok",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:population_simulator, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:population_simulator, ~w(--watch)]}
  ]

config :population_simulator, PopulationSimulatorWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/population_simulator_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]
```

- [ ] **Step 4: Update config/runtime.exs**

```elixir
import Config

config :population_simulator,
  claude_api_key: System.get_env("CLAUDE_API_KEY"),
  claude_model: System.get_env("CLAUDE_MODEL", "claude-haiku-4-5-20251001"),
  llm_concurrency: String.to_integer(System.get_env("LLM_CONCURRENCY", "30"))

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE not set"

  config :population_simulator, PopulationSimulatorWeb.Endpoint,
    secret_key_base: secret_key_base
end
```

- [ ] **Step 5: Update application.ex to add PubSub and Endpoint**

```elixir
defmodule PopulationSimulator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PopulationSimulator.Repo,
      {Phoenix.PubSub, name: PopulationSimulator.PubSub},
      {Registry, keys: :unique, name: PopulationSimulator.ActorRegistry},
      {DynamicSupervisor, name: PopulationSimulator.Actors.PopulationSupervisor, strategy: :one_for_one},
      PopulationSimulatorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PopulationSimulator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

- [ ] **Step 6: Install dependencies**

Run: `mix deps.get`
Expected: Dependencies fetched successfully.

- [ ] **Step 7: Commit**

```bash
git add mix.exs mix.lock config/ lib/population_simulator/application.ex
git commit -m "Add Phoenix, LiveView, Tailwind, esbuild dependencies and config"
```

---

### Task 2: Phoenix Endpoint, Router, Error handling

**Files:**
- Create: `lib/population_simulator_web/endpoint.ex`
- Create: `lib/population_simulator_web/router.ex`
- Create: `lib/population_simulator_web/error_html.ex`

- [ ] **Step 1: Create Endpoint**

```elixir
defmodule PopulationSimulatorWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :population_simulator

  @session_options [
    store: :cookie,
    key: "_population_simulator_key",
    signing_salt: "population_sim",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :population_simulator,
    gzip: false,
    only: PopulationSimulatorWeb.static_paths()

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PopulationSimulatorWeb.Router

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
end
```

- [ ] **Step 2: Create Router**

```elixir
defmodule PopulationSimulatorWeb.Router do
  use Phoenix.Router, helpers: false

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PopulationSimulatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", PopulationSimulatorWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/actors", ActorsLive, :index
    live "/run", RunMeasureLive, :index
    live "/settings", SettingsLive, :index
  end
end
```

- [ ] **Step 3: Create ErrorHTML**

```elixir
defmodule PopulationSimulatorWeb.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
```

- [ ] **Step 4: Verify it compiles**

Run: `mix compile`
Expected: Compiles (will have warnings about missing modules — that's ok for now).

- [ ] **Step 5: Commit**

```bash
git add lib/population_simulator_web/
git commit -m "Add Phoenix endpoint, router, and error handling"
```

---

### Task 3: Layouts and Tailwind/JS assets

**Files:**
- Create: `lib/population_simulator_web/components/layouts.ex`
- Create: `lib/population_simulator_web/components/layouts/root.html.heex`
- Create: `lib/population_simulator_web/components/layouts/app.html.heex`
- Create: `assets/css/app.css`
- Create: `assets/js/app.js`
- Create: `assets/tailwind.config.js`
- Create: `priv/static/favicon.ico` (empty)

- [ ] **Step 1: Create Layouts module**

```elixir
defmodule PopulationSimulatorWeb.Layouts do
  use Phoenix.Component
  import PopulationSimulatorWeb.CoreComponents

  embed_templates "layouts/*"
end
```

- [ ] **Step 2: Create root layout**

Create `lib/population_simulator_web/components/layouts/root.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en" class="h-full">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <title>Population Simulator</title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
  </head>
  <body class="h-full bg-[#1a1a2e] text-gray-200">
    <%= @inner_content %>
  </body>
</html>
```

- [ ] **Step 3: Create app layout with sidebar**

Create `lib/population_simulator_web/components/layouts/app.html.heex`:

```heex
<div class="flex h-screen overflow-hidden">
  <!-- Sidebar -->
  <aside class="w-64 bg-[#16213e] flex flex-col border-r border-gray-700/50 flex-shrink-0">
    <!-- Header -->
    <div class="p-4 border-b border-gray-700/50">
      <h1 class="text-lg font-bold text-[#00d2ff]">Population Simulator</h1>
    </div>

    <!-- Populations -->
    <div class="p-4 flex-1 overflow-y-auto">
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs uppercase tracking-wider text-gray-500">Populations</span>
      </div>
      <div id="population-list" class="space-y-1 mb-6">
        <!-- Populated by LiveView -->
      </div>

      <!-- Navigation -->
      <nav class="space-y-1">
        <.nav_link href={~p"/"} active={@active_page == :dashboard}>
          Dashboard
        </.nav_link>
        <.nav_link href={~p"/actors"} active={@active_page == :actors}>
          Actors
        </.nav_link>
        <.nav_link href={~p"/run"} active={@active_page == :run}>
          Run Measure
        </.nav_link>
        <.nav_link href={~p"/settings"} active={@active_page == :settings}>
          Settings
        </.nav_link>
      </nav>
    </div>

    <!-- API Key indicator -->
    <div class="p-4 border-t border-gray-700/50">
      <div class="flex items-center gap-2 text-xs text-gray-500">
        <div class={"w-2 h-2 rounded-full #{if @api_key_configured?, do: "bg-green-500", else: "bg-red-500"}"}></div>
        <%= if @api_key_configured?, do: "API Key configured", else: "No API Key" %>
      </div>
    </div>
  </aside>

  <!-- Main content -->
  <main class="flex-1 overflow-y-auto p-6">
    <.flash_group flash={@flash} />
    <%= @inner_content %>
  </main>
</div>
```

- [ ] **Step 4: Create assets/css/app.css**

```css
@import "tailwindcss/base";
@import "tailwindcss/components";
@import "tailwindcss/utilities";
```

- [ ] **Step 5: Create assets/js/app.js**

```javascript
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

let Hooks = {}

Hooks.Chart = {
  mounted() {
    this.chart = null
    this.renderChart()
  },
  updated() {
    this.renderChart()
  },
  renderChart() {
    const config = JSON.parse(this.el.dataset.chart)
    if (this.chart) {
      this.chart.destroy()
    }
    import("https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js").then(module => {
      const Chart = window.Chart
      const ctx = this.el.getContext("2d")
      this.chart = new Chart(ctx, config)
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

liveSocket.connect()
window.liveSocket = liveSocket
```

- [ ] **Step 6: Create assets/tailwind.config.js**

```javascript
const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/population_simulator_web/**/*.*ex",
    "../lib/population_simulator_web/**/*.heex"
  ],
  theme: {
    extend: {},
  },
  plugins: []
}
```

- [ ] **Step 7: Create empty favicon and static dirs**

Run: `mkdir -p priv/static/assets && touch priv/static/favicon.ico`

- [ ] **Step 8: Install tailwind and esbuild, build assets**

Run: `mix assets.setup && mix assets.build`
Expected: Tailwind and esbuild installed, assets built.

- [ ] **Step 9: Commit**

```bash
git add lib/population_simulator_web/components/ assets/ priv/static/
git commit -m "Add layouts, sidebar, Tailwind CSS, and JS assets with Chart.js hook"
```

---

### Task 4: CoreComponents and LiveView helpers

**Files:**
- Create: `lib/population_simulator_web/components/core_components.ex`

- [ ] **Step 1: Create core UI components**

```elixir
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
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator_web/components/core_components.ex
git commit -m "Add core UI components (nav_link, mood_gauge, card, flash)"
```

---

### Task 5: Settings LiveView

**Files:**
- Create: `lib/population_simulator_web/live/settings_live.ex`

- [ ] **Step 1: Create SettingsLive**

```elixir
defmodule PopulationSimulatorWeb.SettingsLive do
  use Phoenix.LiveView
  import PopulationSimulatorWeb.CoreComponents

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
```

- [ ] **Step 2: Test manually**

Run: `mix phx.server`
Open: `http://localhost:4000/settings`
Expected: Settings page with API key input and model dropdown.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator_web/live/settings_live.ex
git commit -m "Add Settings LiveView for API key and model config"
```

---

### Task 6: Dashboard LiveView

**Files:**
- Create: `lib/population_simulator_web/live/dashboard_live.ex`

- [ ] **Step 1: Create DashboardLive**

```elixir
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
```

- [ ] **Step 2: Test manually**

Run: `mix phx.server`
Open: `http://localhost:4000`
Expected: Dashboard with population pills. Click a population to see mood gauges, charts, beliefs, emergent concepts, voices.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator_web/live/dashboard_live.ex
git commit -m "Add Dashboard LiveView with mood gauges, charts, beliefs, and actor voices"
```

---

### Task 7: Actors LiveView with table/grid toggle and actor detail

**Files:**
- Create: `lib/population_simulator_web/live/actors_live.ex`

- [ ] **Step 1: Create ActorsLive**

```elixir
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
       selected_actor: nil
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
```

- [ ] **Step 2: Test manually**

Open: `http://localhost:4000/actors`
Expected: Actor list with filters, table/grid toggle, click opens slide-over detail.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator_web/live/actors_live.ex
git commit -m "Add Actors LiveView with table/grid toggle, filters, and detail panel"
```

---

### Task 8: Run Measure LiveView with live progress

**Files:**
- Create: `lib/population_simulator_web/live/run_measure_live.ex`
- Modify: `lib/population_simulator/simulation/measure_runner.ex`

- [ ] **Step 1: Add PubSub broadcasting to MeasureRunner**

In `lib/population_simulator/simulation/measure_runner.ex`, add a counter and broadcast. Replace the `run/2` function:

Add after the `alias` block at the top:

```elixir
  @broadcast_every 10
```

In the `evaluate_actor` function, after the `Repo.insert_all(Decision, ...)` call, add broadcasting. The simplest way: modify the reducer in `run/2` to broadcast:

Replace the reducer block in `run/2`:

```elixir
    results =
      actors
      |> Task.async_stream(
        fn actor -> evaluate_actor(actor, measure, measure_id, relevant_nodes) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0, tokens: 0, errors: []}, fn
        {:ok, {:ok, _, tokens}}, acc ->
          acc = %{acc | ok: acc.ok + 1, tokens: acc.tokens + (tokens || 0)}
          maybe_broadcast(measure_id, acc, total)
          acc

        {:ok, {:error, id, reason}}, acc ->
          %{acc | error: acc.error + 1, errors: [{id, reason} | acc.errors]}

        {:exit, _}, acc ->
          %{acc | error: acc.error + 1}
      end)
```

Add this private function:

```elixir
  defp maybe_broadcast(measure_id, acc, total) do
    if rem(acc.ok, @broadcast_every) == 0 do
      Phoenix.PubSub.broadcast(
        PopulationSimulator.PubSub,
        "simulation:#{measure_id}",
        {:simulation_progress, %{ok: acc.ok, error: acc.error, total: total, tokens: acc.tokens}}
      )
    end
  end
```

- [ ] **Step 2: Create RunMeasureLive**

```elixir
defmodule PopulationSimulatorWeb.RunMeasureLive do
  use Phoenix.LiveView
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
      population = Repo.get!(Population, pop_id)

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
```

- [ ] **Step 3: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 4: Commit**

```bash
git add lib/population_simulator_web/live/run_measure_live.ex lib/population_simulator/simulation/measure_runner.ex
git commit -m "Add Run Measure LiveView with live progress via PubSub"
```

---

### Task 9: Wire everything together and verify

- [ ] **Step 1: Ensure all pages load**

Run: `mix phx.server`

Test each page:
- `http://localhost:4000/` — Dashboard
- `http://localhost:4000/actors` — Actors
- `http://localhost:4000/run` — Run Measure
- `http://localhost:4000/settings` — Settings

Expected: All pages load with dark theme, sidebar visible on all pages.

- [ ] **Step 2: Test the full flow**

1. Go to Settings, enter API key, select model, save
2. Go to Dashboard, click a population, see mood gauges and charts
3. Go to Actors, filter by stratum, toggle to grid view, click an actor
4. Go to Run Measure, fill form, run (if API key available)

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "Wire up all LiveView pages and verify full dashboard flow"
```
