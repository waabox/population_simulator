defmodule PopulationSimulator.Simulation.ActorBelief do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actor_beliefs" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :decision, PopulationSimulator.Simulation.Decision, type: :binary_id
    belongs_to :measure, PopulationSimulator.Simulation.Measure, type: :binary_id
    field :graph, :map
    timestamps(type: :utc_datetime)
  end

  def changeset(belief, attrs) do
    belief
    |> cast(attrs, [:actor_id, :decision_id, :measure_id, :graph])
    |> validate_required([:actor_id, :graph])
  end

  def initial(actor_id, graph) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: nil,
      measure_id: nil,
      graph: graph,
      inserted_at: now,
      updated_at: now
    }
  end

  def from_update(actor_id, decision_id, measure_id, graph) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: decision_id,
      measure_id: measure_id,
      graph: graph,
      inserted_at: now,
      updated_at: now
    }
  end
end
