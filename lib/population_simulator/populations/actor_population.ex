defmodule PopulationSimulator.Populations.ActorPopulation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actor_populations" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :population, PopulationSimulator.Populations.Population, type: :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(actor_population, attrs) do
    actor_population
    |> cast(attrs, [:actor_id, :population_id])
    |> validate_required([:actor_id, :population_id])
    |> unique_constraint([:actor_id, :population_id])
  end
end
