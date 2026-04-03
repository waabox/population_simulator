defmodule PopulationSimulator.Simulation.ActorSummary do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_summaries" do
    belongs_to :actor, PopulationSimulator.Actors.Actor
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    field :narrative, :string
    field :self_observations, :string
    field :version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [:actor_id, :measure_id, :narrative, :self_observations, :version])
    |> validate_required([:actor_id, :narrative, :self_observations, :version])
  end

  def new(actor_id, measure_id, narrative, self_observations, version) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      narrative: narrative,
      self_observations: Jason.encode!(self_observations),
      version: version,
      inserted_at: now,
      updated_at: now
    }
  end
end
