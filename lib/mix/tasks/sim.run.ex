defmodule Mix.Tasks.Sim.Run do
  use Mix.Task

  @shortdoc "Runs an economic measure against the population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [title: :string, description: :string, concurrency: :integer, limit: :integer]
      )

    description = opts[:description] || raise "Required: --description"
    title = opts[:title] || "Medida"
    concurrency = opts[:concurrency] || 30
    limit = opts[:limit]

    {:ok, measure} =
      PopulationSimulator.Repo.insert(
        PopulationSimulator.Simulation.Measure.changeset(
          %PopulationSimulator.Simulation.Measure{},
          %{title: title, description: description}
        )
      )

    IO.puts("Measure: #{title}")
    IO.puts("#{description}\n")

    run_opts = [concurrency: concurrency]
    run_opts = if limit, do: Keyword.put(run_opts, :limit, limit), else: run_opts

    {:ok, results} = PopulationSimulator.Simulation.MeasureRunner.run(measure.id, run_opts)

    if results.ok > 0 do
      {:ok, metrics} = PopulationSimulator.Metrics.Aggregator.summary(measure.id)
      IO.inspect(metrics, label: "Metrics", pretty: true)
    end
  end
end
