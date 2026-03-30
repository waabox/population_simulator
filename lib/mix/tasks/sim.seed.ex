defmodule Mix.Tasks.Sim.Seed do
  use Mix.Task

  @shortdoc "Seeds population from INDEC EPH files"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [n: :integer, individual: :string, hogar: :string, population: :string]
      )

    n = opts[:n] || 5_000
    individual = opts[:individual] || "priv/data/eph/individual.txt"
    hogar = opts[:hogar] || "priv/data/eph/hogar.txt"
    population_name = opts[:population]

    IO.puts("Loading EPH GBA...")
    individuos = PopulationSimulator.DataPipeline.EphLoader.load(individual, hogar)
    IO.puts("#{length(individuos)} individuals found in EPH sample")

    IO.puts("Sampling #{n} weighted actors...")
    sample = PopulationSimulator.DataPipeline.PopulationSampler.sample(n, individuos)

    IO.puts("Enriching with synthetic variables...")
    actores = Enum.map(sample, &PopulationSimulator.DataPipeline.ActorEnricher.enrich/1)

    IO.puts("Persisting to DB...")
    rows = PopulationSimulator.Actors.Actor.insert_all(actores)

    IO.puts("Creating initial moods...")
    create_initial_moods(rows)

    if population_name do
      assign_to_population(rows, population_name)
    end

    IO.puts("Population of #{n} actors created from real EPH GBA data")

    print_distribution("Stratum", actores, :stratum)
    print_distribution("Zone", actores, :zone)
    print_distribution("Employment", actores, :employment_type)
  end

  defp create_initial_moods(rows) do
    alias PopulationSimulator.{Repo, Simulation.ActorMood}

    rows
    |> Enum.map(fn row -> ActorMood.initial_from_profile(row[:id], row[:profile]) end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(ActorMood, chunk, on_conflict: :nothing)
    end)
  end

  defp assign_to_population(rows, population_name) do
    alias PopulationSimulator.{Repo, Populations.Population, Populations.ActorPopulation}

    population =
      case Repo.get_by(Population, name: population_name) do
        nil ->
          {:ok, p} = Repo.insert(Population.changeset(%Population{}, %{name: population_name}))
          IO.puts("Population '#{population_name}' created.")
          p

        existing ->
          existing
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows
    |> Enum.map(fn row ->
      %{
        id: Ecto.UUID.generate(),
        actor_id: row[:id],
        population_id: population.id,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(ActorPopulation, chunk,
        on_conflict: :nothing,
        conflict_target: [:actor_id, :population_id]
      )
    end)

    IO.puts("Assigned #{length(rows)} actors to population '#{population_name}'")
  end

  defp print_distribution(label, actores, key) do
    dist =
      actores
      |> Enum.group_by(&Map.get(&1, key))
      |> Enum.map(fn {k, v} -> {k, length(v)} end)
      |> Enum.sort_by(fn {_, count} -> -count end)

    IO.puts("\n--- #{label} ---")

    Enum.each(dist, fn {k, count} ->
      pct = Float.round(count / length(actores) * 100, 1)
      IO.puts("  #{k}: #{count} (#{pct}%)")
    end)
  end
end
