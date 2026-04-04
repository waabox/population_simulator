defmodule PopulationSimulator.Simulation.ActorPerception do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "actor_perceptions" do
    belongs_to :actor, PopulationSimulator.Actors.Actor
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    belongs_to :cafe_session, PopulationSimulator.Simulation.CafeSession
    belongs_to :referent, PopulationSimulator.Actors.Actor
    field :group_mood, :string
    field :referent_influence, :string
    timestamps(type: :utc_datetime)
  end
  def changeset(perception, attrs) do
    perception
    |> cast(attrs, [:actor_id, :measure_id, :cafe_session_id, :group_mood, :referent_id, :referent_influence])
    |> validate_required([:actor_id, :measure_id, :cafe_session_id, :group_mood])
  end
  def new(actor_id, measure_id, cafe_session_id, group_mood, referent_id, referent_influence) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    %{id: Ecto.UUID.generate(), actor_id: actor_id, measure_id: measure_id,
      cafe_session_id: cafe_session_id, group_mood: Jason.encode!(group_mood),
      referent_id: referent_id, referent_influence: referent_influence,
      inserted_at: now, updated_at: now}
  end
end
