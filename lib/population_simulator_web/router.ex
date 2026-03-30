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
