defmodule Mix.Tasks.Sim.Seed do
  use Mix.Task

  @shortdoc "Seeds population from INDEC EPH files"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [n: :integer, individual: :string, hogar: :string]
      )

    n = opts[:n] || 5_000
    individual = opts[:individual] || "priv/data/eph/individual.txt"
    hogar = opts[:hogar] || "priv/data/eph/hogar.txt"

    IO.puts("Loading EPH GBA...")
    individuos = PopulationSimulator.DataPipeline.EphLoader.load(individual, hogar)
    IO.puts("#{length(individuos)} individuals found in EPH sample")

    IO.puts("Sampling #{n} weighted actors...")
    sample = PopulationSimulator.DataPipeline.PopulationSampler.sample(n, individuos)

    IO.puts("Enriching with synthetic variables...")
    actores = Enum.map(sample, &PopulationSimulator.DataPipeline.ActorEnricher.enrich/1)

    IO.puts("Persisting to DB...")
    PopulationSimulator.Actors.Actor.insert_all(actores)

    IO.puts("Population of #{n} actors created from real EPH GBA data")

    # Print distribution summary
    print_distribution("Estrato", actores, :estrato)
    print_distribution("Zona", actores, :zona)
    print_distribution("Empleo", actores, :tipo_empleo)
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
