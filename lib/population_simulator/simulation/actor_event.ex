defmodule PopulationSimulator.Simulation.ActorEvent do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "actor_events" do
    belongs_to :actor, PopulationSimulator.Actors.Actor
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    field :description, :string
    field :mood_impact, :string
    field :profile_effects, :string
    field :duration, :integer
    field :remaining, :integer
    field :active, :boolean, default: true
    timestamps(type: :utc_datetime)
  end
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :measure_id, :description, :mood_impact, :profile_effects, :duration, :remaining, :active])
    |> validate_required([:actor_id, :measure_id, :description, :mood_impact, :profile_effects, :duration, :remaining])
  end
  def new(actor_id, measure_id, description, mood_impact, profile_effects, duration) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    %{id: Ecto.UUID.generate(), actor_id: actor_id, measure_id: measure_id, description: description,
      mood_impact: Jason.encode!(mood_impact), profile_effects: Jason.encode!(profile_effects),
      duration: duration, remaining: duration, active: true, inserted_at: now, updated_at: now}
  end
end
