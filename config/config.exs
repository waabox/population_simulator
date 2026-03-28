import Config

config :population_simulator,
  ecto_repos: [PopulationSimulator.Repo]

config :population_simulator, PopulationSimulator.Repo,
  database: Path.expand("../population_simulator_dev.db", __DIR__),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

import_config "#{config_env()}.exs"
