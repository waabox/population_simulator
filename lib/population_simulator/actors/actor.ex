defmodule PopulationSimulator.Actors.Actor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actors" do
    field :profile, :map
    field :prompt_base, :string
    field :estrato, :string
    field :zona, :string
    field :edad, :integer
    field :tipo_empleo, :string
    field :tenencia, :string
    field :orientacion_politica, :integer
    field :recibe_plan, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  def changeset(actor, attrs) do
    actor
    |> cast(attrs, [
      :profile,
      :prompt_base,
      :estrato,
      :zona,
      :edad,
      :tipo_empleo,
      :tenencia,
      :orientacion_politica,
      :recibe_plan
    ])
    |> validate_required([:profile])
  end

  def from_enriched(data) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    profile =
      data
      |> Map.drop([:codusu, :aglomerado])
      |> stringify_keys()

    %{
      id: Ecto.UUID.generate(),
      profile: profile,
      estrato: to_string(data.estrato),
      zona: to_string(data.zona),
      edad: data.edad,
      tipo_empleo: to_string(data.tipo_empleo),
      tenencia: to_string(data.tenencia),
      orientacion_politica: data.orientacion_politica,
      recibe_plan: data[:recibe_plan_social] || false,
      inserted_at: now,
      updated_at: now
    }
  end

  def insert_all(actores) do
    actores
    |> Enum.map(&from_enriched/1)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      PopulationSimulator.Repo.insert_all(__MODULE__, chunk,
        on_conflict: :nothing,
        conflict_target: [:id]
      )
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_map(v) -> {to_string(k), stringify_keys(v)}
      {k, v} when is_atom(v) -> {to_string(k), to_string(v)}
      {k, v} -> {to_string(k), v}
    end)
  end
end
