defmodule PopulationSimulator.Simulation.Measure do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "measures" do
    field :title, :string
    field :description, :string
    field :category, :string
    field :tags, :string
    field :measure_date, :date
    belongs_to :population, PopulationSimulator.Populations.Population, type: :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(measure, attrs) do
    measure
    |> cast(attrs, [:title, :description, :category, :tags, :population_id, :measure_date])
    |> validate_required([:title, :description])
  end
end
