defmodule PopulationSimulator.Populations.Population do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "populations" do
    field :name, :string
    field :description, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(population, attrs) do
    population
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
