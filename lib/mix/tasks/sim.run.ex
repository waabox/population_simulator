defmodule Mix.Tasks.Sim.Run do
  use Mix.Task

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
          population: :string
        ]
      )

    description = opts[:description] || raise "Required: --description"
    title = opts[:title] || "Medida"
    concurrency = opts[:concurrency] || 30
    limit = opts[:limit]
    population_name = opts[:population]

    population_id = resolve_population_id(population_name)

    measure_attrs = %{title: title, description: description}
    measure_attrs = if population_id, do: Map.put(measure_attrs, :population_id, population_id), else: measure_attrs

    {:ok, measure} =
      PopulationSimulator.Repo.insert(
        PopulationSimulator.Simulation.Measure.changeset(
          %PopulationSimulator.Simulation.Measure{},
          measure_attrs
        )
      )

    IO.puts("Measure: #{title}")
    if population_name, do: IO.puts("Population: #{population_name}")
    IO.puts("#{description}\n")

    run_opts = [concurrency: concurrency]
    run_opts = if population_id, do: Keyword.put(run_opts, :population_id, population_id), else: run_opts
    run_opts = if limit, do: Keyword.put(run_opts, :limit, limit), else: run_opts

    {:ok, results} = PopulationSimulator.Simulation.MeasureRunner.run(measure.id, run_opts)

    if results.ok > 0 do
      {:ok, metrics} = PopulationSimulator.Metrics.Aggregator.summary(measure.id)
      IO.inspect(metrics, label: "Metrics", pretty: true)
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
