import Config

config :population_simulator, PopulationSimulator.Repo,
  database: Path.expand("../population_simulator_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox
