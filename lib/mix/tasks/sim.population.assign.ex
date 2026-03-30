defmodule Mix.Tasks.Sim.Population.Assign do
  use Mix.Task

  @shortdoc "Assigns actors to a population (with optional filters)"

  import Ecto.Query

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          name: :string,
          limit: :integer,
          zone: :string,
          stratum: :string,
          employment_type: :string,
          age_min: :integer,
          age_max: :integer
        ]
      )

    name = opts[:name] || raise "Required: --name"

    alias PopulationSimulator.{Repo, Actors.Actor, Populations.Population}

    population =
      Repo.get_by!(Population, name: name)

    query = from(a in Actor, select: a.id)
    query = apply_filters(query, opts)
    query = if opts[:limit], do: from(q in query, order_by: fragment("RANDOM()"), limit: ^opts[:limit]), else: query

    actor_ids = Repo.all(query)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(actor_ids, fn actor_id ->
        %{
          id: Ecto.UUID.generate(),
          actor_id: actor_id,
          population_id: population.id,
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(PopulationSimulator.Populations.ActorPopulation, chunk,
        on_conflict: :nothing,
        conflict_target: [:actor_id, :population_id]
      )
    end)

    IO.puts("Assigned #{length(actor_ids)} actors to population '#{name}'")
  end

  defp apply_filters(query, opts) do
    query
    |> filter_zone(opts[:zone])
    |> filter_stratum(opts[:stratum])
    |> filter_employment(opts[:employment_type])
    |> filter_age_min(opts[:age_min])
    |> filter_age_max(opts[:age_max])
  end

  defp filter_zone(query, nil), do: query
  defp filter_zone(query, zones) do
    zone_list = String.split(zones, ",")
    from(a in query, where: a.zone in ^zone_list)
  end

  defp filter_stratum(query, nil), do: query
  defp filter_stratum(query, strata) do
    stratum_list = String.split(strata, ",")
    from(a in query, where: a.stratum in ^stratum_list)
  end

  defp filter_employment(query, nil), do: query
  defp filter_employment(query, types) do
    type_list = String.split(types, ",")
    from(a in query, where: a.employment_type in ^type_list)
  end

  defp filter_age_min(query, nil), do: query
  defp filter_age_min(query, min), do: from(a in query, where: a.age >= ^min)

  defp filter_age_max(query, nil), do: query
  defp filter_age_max(query, max), do: from(a in query, where: a.age <= ^max)
end
