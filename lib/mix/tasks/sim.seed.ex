defmodule Mix.Tasks.Sim.Seed do
  use Mix.Task

  @shortdoc "Seeds population from INDEC EPH files"

  @template_dir "priv/data/belief_templates"

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

    IO.puts("Creating initial belief graphs...")
    create_initial_beliefs(rows)

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

  defp create_initial_beliefs(rows) do
    alias PopulationSimulator.{Repo, Simulation.ActorBelief, Simulation.BeliefGraph}

    templates = load_templates()

    if templates == %{} do
      IO.puts("  No belief templates found in #{@template_dir}/ — skipping. Run mix sim.beliefs.init first.")
      return_early()
    else
      rows
      |> Enum.map(fn row ->
        archetype = resolve_archetype(row[:profile])
        template = Map.get(templates, archetype, Map.get(templates, "middle_right", default_graph()))
        graph = BeliefGraph.from_template(template, row[:profile])
        ActorBelief.initial(row[:id], graph)
      end)
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(ActorBelief, chunk, on_conflict: :nothing)
      end)
    end
  end

  defp load_templates do
    if File.dir?(@template_dir) do
      @template_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Map.new(fn filename ->
        name = String.replace_suffix(filename, ".json", "")
        content = @template_dir |> Path.join(filename) |> File.read!() |> Jason.decode!()
        {name, content}
      end)
    else
      %{}
    end
  end

  defp resolve_archetype(profile) do
    stratum = profile["stratum"]
    orientation = profile["political_orientation"] || 5

    stratum_group = cond do
      stratum in ["destitute", "low"] -> "destitute"
      stratum == "lower_middle" -> "lower_middle"
      stratum == "middle" -> "middle"
      stratum in ["upper_middle", "upper"] -> "upper"
      true -> "middle"
    end

    orientation_group = if orientation <= 5, do: "left", else: "right"

    "#{stratum_group}_#{orientation_group}"
  end

  defp default_graph do
    %{
      "nodes" => Enum.map(PopulationSimulator.Simulation.BeliefGraph.core_nodes(), fn id ->
        %{"id" => id, "type" => "core"}
      end),
      "edges" => []
    }
  end

  defp return_early, do: :ok

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
