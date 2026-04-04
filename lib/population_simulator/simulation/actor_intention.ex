defmodule PopulationSimulator.Simulation.ActorIntention do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_intentions" do
    belongs_to :actor, PopulationSimulator.Actors.Actor
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    field :description, :string
    field :profile_effects, :string
    field :urgency, :string, default: "medium"
    field :status, :string, default: "pending"
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(intention, attrs) do
    intention
    |> cast(attrs, [
      :actor_id,
      :measure_id,
      :description,
      :profile_effects,
      :urgency,
      :status,
      :resolved_at
    ])
    |> validate_required([
      :actor_id,
      :measure_id,
      :description,
      :profile_effects,
      :urgency,
      :status
    ])
    |> validate_inclusion(:status, ["pending", "executed", "frustrated", "expired"])
    |> validate_inclusion(:urgency, ["high", "medium", "low"])
  end

  def new(actor_id, measure_id, description, profile_effects, urgency) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      description: description,
      profile_effects: Jason.encode!(profile_effects),
      urgency: urgency || "medium",
      status: "pending",
      resolved_at: nil,
      inserted_at: now,
      updated_at: now
    }
  end
end
