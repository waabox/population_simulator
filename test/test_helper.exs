Ecto.Migrator.run(
  PopulationSimulator.Repo,
  Path.join(:code.priv_dir(:population_simulator), "repo/migrations"),
  :up,
  all: true,
  log: false
)

ExUnit.start()
