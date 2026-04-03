defmodule PopulationSimulator.Simulation.CafeSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias PopulationSimulator.Simulation.CafeEffect

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cafe_sessions" do
    belongs_to :measure, PopulationSimulator.Simulation.Measure
    has_many :effects, CafeEffect
    field :group_key, :string
    field :participant_ids, :string
    field :participant_names, :string
    field :conversation, :string
    field :conversation_summary, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:measure_id, :group_key, :participant_ids, :participant_names, :conversation, :conversation_summary])
    |> validate_required([:measure_id, :group_key, :participant_ids, :participant_names, :conversation, :conversation_summary])
  end

  def new(measure_id, group_key, participant_ids, participant_names, conversation, summary) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      measure_id: measure_id,
      group_key: group_key,
      participant_ids: Jason.encode!(participant_ids),
      participant_names: Jason.encode!(participant_names),
      conversation: Jason.encode!(conversation),
      conversation_summary: summary,
      inserted_at: now,
      updated_at: now
    }
  end
end
