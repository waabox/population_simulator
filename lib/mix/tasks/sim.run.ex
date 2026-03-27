defmodule Mix.Tasks.Sim.Run do
  use Mix.Task

  @shortdoc "Runs an economic measure against the population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [titulo: :string, descripcion: :string, concurrency: :integer, limit: :integer]
      )

    descripcion = opts[:descripcion] || raise "Required: --descripcion"
    titulo = opts[:titulo] || "Medida"
    concurrency = opts[:concurrency] || 30
    limit = opts[:limit]

    {:ok, measure} =
      PopulationSimulator.Repo.insert(
        PopulationSimulator.Simulation.Measure.changeset(
          %PopulationSimulator.Simulation.Measure{},
          %{titulo: titulo, descripcion: descripcion}
        )
      )

    IO.puts("Measure: #{titulo}")
    IO.puts("#{descripcion}\n")

    run_opts = [concurrency: concurrency]
    run_opts = if limit, do: Keyword.put(run_opts, :limit, limit), else: run_opts

    {:ok, results} = PopulationSimulator.Simulation.MeasureRunner.run(measure.id, run_opts)

    if results.ok > 0 do
      {:ok, metrics} = PopulationSimulator.Metrics.Aggregator.resumen(measure.id)
      IO.inspect(metrics, label: "Metrics", pretty: true)
    end
  end
end
