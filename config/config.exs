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
