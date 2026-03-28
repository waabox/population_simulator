defmodule PopulationSimulator.Simulation.Measure do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "measures" do
    field :title, :string
    field :description, :string
    field :category, :string
    field :tags, {:array, :string}
    timestamps(type: :utc_datetime)
  end

  def changeset(measure, attrs) do
    measure
    |> cast(attrs, [:title, :description, :category, :tags])
    |> validate_required([:title, :description])
  end
end
