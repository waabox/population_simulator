defmodule PopulationSimulator.Simulation.ActorBond do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "actor_bonds" do
    belongs_to :actor_a, PopulationSimulator.Actors.Actor
    belongs_to :actor_b, PopulationSimulator.Actors.Actor
    field :affinity, :float, default: 0.1
    field :shared_cafes, :integer, default: 1
    field :formed_at, :utc_datetime
    field :last_cafe_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
  def changeset(bond, attrs) do
    bond
    |> cast(attrs, [:actor_a_id, :actor_b_id, :affinity, :shared_cafes, :formed_at, :last_cafe_at])
    |> validate_required([:actor_a_id, :actor_b_id, :affinity, :shared_cafes, :last_cafe_at])
    |> unique_constraint([:actor_a_id, :actor_b_id])
  end
  def ordered_pair(id1, id2) when id1 < id2, do: {id1, id2}
  def ordered_pair(id1, id2), do: {id2, id1}
end
