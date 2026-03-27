defmodule PopulationSimulator.Simulation.Measure do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "measures" do
    field :titulo, :string
    field :descripcion, :string
    field :categoria, :string
    field :tags, {:array, :string}
    timestamps(type: :utc_datetime)
  end

  def changeset(measure, attrs) do
    measure
    |> cast(attrs, [:titulo, :descripcion, :categoria, :tags])
    |> validate_required([:titulo, :descripcion])
  end
end
