import Config

config :population_simulator,
  ecto_repos: [PopulationSimulator.Repo]

config :population_simulator, PopulationSimulator.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "population_simulator_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

import_config "#{config_env()}.exs"
