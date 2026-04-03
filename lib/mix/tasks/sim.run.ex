defmodule Mix.Tasks.Sim.Run do
  use Mix.Task

  import Ecto.Query

  @shortdoc "Runs an economic measure against the population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          title: :string,
          description: :string,
          concurrency: :integer,
          limit: :integer,
          population: :string,
          date: :string,
          cafe: :boolean
        ]
      )

    description = opts[:description] || raise "Required: --description"
    title = opts[:title] || "Medida"
    concurrency = opts[:concurrency] || 30
    limit = opts[:limit]
    population_name = opts[:population]

    measure_date = parse_date(opts[:date])
    population_id = resolve_population_id(population_name)

    measure_attrs = %{title: title, description: description}
    measure_attrs = if population_id, do: Map.put(measure_attrs, :population_id, population_id), else: measure_attrs
    measure_attrs = if measure_date, do: Map.put(measure_attrs, :measure_date, measure_date), else: measure_attrs

    {:ok, measure} =
      PopulationSimulator.Repo.insert(
        PopulationSimulator.Simulation.Measure.changeset(
          %PopulationSimulator.Simulation.Measure{},
          measure_attrs
        )
      )

    IO.puts("Measure: #{title}")
    if population_name, do: IO.puts("Population: #{population_name}")
    if measure_date, do: IO.puts("Date: #{measure_date}")
    IO.puts("#{description}\n")

    run_opts = [concurrency: concurrency]
    run_opts = if population_id, do: Keyword.put(run_opts, :population_id, population_id), else: run_opts
    run_opts = if limit, do: Keyword.put(run_opts, :limit, limit), else: run_opts

    {:ok, results} = PopulationSimulator.Simulation.MeasureRunner.run(measure.id, run_opts)

    if results.ok > 0 do
      {:ok, metrics} = PopulationSimulator.Metrics.Aggregator.summary(measure.id)
      IO.inspect(metrics, label: "Metrics", pretty: true)
    end

    if Keyword.get(opts, :cafe, false) do
      IO.puts("\nStarting café round...")

      actors = load_actors_for_cafe(population_id)
      decisions = load_decisions_for_measure(measure.id)

      cafe_results =
        PopulationSimulator.Simulation.CafeRunner.run(measure, actors, decisions,
          concurrency: concurrency
        )

      IO.puts("Café: #{cafe_results.ok} tables OK, #{cafe_results.error} errors")

      measure_count =
        PopulationSimulator.Repo.one(
          from(m in PopulationSimulator.Simulation.Measure, select: count(m.id))
        )

      if rem(measure_count, 3) == 0 do
        IO.puts("\nTriggering introspection (measure ##{measure_count})...")

        intro_results =
          PopulationSimulator.Simulation.IntrospectionRunner.run(measure, actors,
            concurrency: concurrency
          )

        IO.puts("Introspection: #{intro_results.ok} actors OK, #{intro_results.error} errors")
      end
    end
  end

  defp load_actors_for_cafe(nil) do
    PopulationSimulator.Repo.all(PopulationSimulator.Actors.Actor)
  end

  defp load_actors_for_cafe(population_id) do
    PopulationSimulator.Repo.all(
      from(a in PopulationSimulator.Actors.Actor,
        join: ap in PopulationSimulator.Populations.ActorPopulation, on: ap.actor_id == a.id,
        where: ap.population_id == ^population_id
      )
    )
  end

  defp load_decisions_for_measure(measure_id) do
    PopulationSimulator.Repo.all(
      from(d in PopulationSimulator.Simulation.Decision,
        where: d.measure_id == ^measure_id
      )
    )
  end

  defp parse_date(nil), do: nil
  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      {:error, _} -> raise "Invalid date format: #{date_str}. Use YYYY-MM-DD."
    end
  end

  defp resolve_population_id(nil), do: nil

  defp resolve_population_id(name) do
    alias PopulationSimulator.{Repo, Populations.Population}

    case Repo.get_by(Population, name: name) do
      nil -> raise "Population '#{name}' not found. Create it first with: mix sim.population.create --name \"#{name}\""
      population -> population.id
    end
  end
end
