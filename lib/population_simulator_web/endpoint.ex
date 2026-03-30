defmodule PopulationSimulatorWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :population_simulator

  @session_options [
    store: :cookie,
    key: "_population_simulator_key",
    signing_salt: "population_sim",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :population_simulator,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

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
