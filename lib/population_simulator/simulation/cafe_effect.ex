defmodule PopulationSimulator.Simulation.CafeEffect do
  use Ecto.Schema
  import Ecto.Changeset

  alias PopulationSimulator.Simulation.CafeSession

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cafe_effects" do
    belongs_to :cafe_session, CafeSession
    belongs_to :actor, PopulationSimulator.Actors.Actor
    field :mood_deltas, :string
    field :belief_deltas, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(effect, attrs) do
    effect
    |> cast(attrs, [:cafe_session_id, :actor_id, :mood_deltas, :belief_deltas])
    |> validate_required([:cafe_session_id, :actor_id, :mood_deltas, :belief_deltas])
  end

  def new(cafe_session_id, actor_id, mood_deltas, belief_deltas) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      cafe_session_id: cafe_session_id,
      actor_id: actor_id,
      mood_deltas: Jason.encode!(mood_deltas),
      belief_deltas: Jason.encode!(belief_deltas),
      inserted_at: now,
      updated_at: now
    }
  end
end
