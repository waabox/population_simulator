defmodule PopulationSimulator.Simulation.Decision do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "decisions" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :measure, PopulationSimulator.Simulation.Measure, type: :binary_id
    field :agreement, :boolean
    field :intensity, :integer
    field :reasoning, :string
    field :personal_impact, :string
    field :behavior_change, :string
    field :raw_response, :map
    field :tokens_used, :integer
    timestamps(type: :utc_datetime)
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [
      :actor_id,
      :measure_id,
      :agreement,
      :intensity,
      :reasoning,
      :personal_impact,
      :behavior_change,
      :raw_response,
      :tokens_used
    ])
    |> validate_required([:actor_id, :measure_id])
    |> validate_number(:intensity, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
  end

  def from_llm_response(actor_id, measure_id, decision) do
    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      agreement: decision.agreement,
      intensity: decision.intensity,
      reasoning: decision.reasoning,
      personal_impact: decision.personal_impact,
      behavior_change: decision.behavior_change,
      raw_response: decision.raw_response,
      tokens_used: decision.tokens_used,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end
