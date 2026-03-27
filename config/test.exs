import Config

config :population_simulator, PopulationSimulator.Repo,
  database: "population_simulator_test",
  pool: Ecto.Adapters.SQL.Sandbox
