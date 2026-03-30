defmodule PopulationSimulatorWeb.Layouts do
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: PopulationSimulatorWeb.Endpoint, router: PopulationSimulatorWeb.Router
  import Phoenix.Controller, only: [get_csrf_token: 0]
  import PopulationSimulatorWeb.CoreComponents

  embed_templates "layouts/*"
end
