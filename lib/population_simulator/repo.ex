defmodule PopulationSimulator.Repo do
  use Ecto.Repo,
    otp_app: :population_simulator,
    adapter: Ecto.Adapters.Postgres
end
