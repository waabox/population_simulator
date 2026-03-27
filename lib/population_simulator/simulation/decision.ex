defmodule PopulationSimulator.Simulation.Decision do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "decisions" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :measure, PopulationSimulator.Simulation.Measure, type: :binary_id
    field :acuerdo, :boolean
    field :intensidad, :integer
    field :razon, :string
    field :impacto_personal, :string
    field :cambio_comportamiento, :string
    field :raw_response, :map
    field :tokens_usados, :integer
    timestamps(type: :utc_datetime)
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [
      :actor_id,
      :measure_id,
      :acuerdo,
      :intensidad,
      :razon,
      :impacto_personal,
      :cambio_comportamiento,
      :raw_response,
      :tokens_usados
    ])
    |> validate_required([:actor_id, :measure_id])
  end

  def from_llm_response(actor_id, measure_id, decision) do
    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      measure_id: measure_id,
      acuerdo: decision.acuerdo,
      intensidad: decision.intensidad,
      razon: decision.razon,
      impacto_personal: decision.impacto_personal,
      cambio_comportamiento: decision.cambio_comportamiento,
      raw_response: decision.raw_response,
      tokens_usados: decision.tokens_usados,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end
