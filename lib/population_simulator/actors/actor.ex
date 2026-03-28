defmodule PopulationSimulator.Actors.Actor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actors" do
    field :profile, :map
    field :prompt_base, :string
    field :stratum, :string
    field :zone, :string
    field :age, :integer
    field :employment_type, :string
    field :tenure, :string
    field :political_orientation, :integer
    field :receives_benefit, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  def changeset(actor, attrs) do
    actor
    |> cast(attrs, [
      :profile,
      :prompt_base,
      :stratum,
      :zone,
      :age,
      :employment_type,
      :tenure,
      :political_orientation,
      :receives_benefit
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
      stratum: to_string(data.stratum),
      zone: to_string(data.zone),
      age: data.age,
      employment_type: to_string(data.employment_type),
      tenure: to_string(data.tenure),
      political_orientation: data.political_orientation,
      receives_benefit: data[:receives_welfare] || false,
      inserted_at: now,
      updated_at: now
    }
  end

  def insert_all(actors) do
    actors
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
