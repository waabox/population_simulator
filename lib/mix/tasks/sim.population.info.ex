defmodule Mix.Tasks.Sim.Population.Info do
  use Mix.Task

  @shortdoc "Shows composition of a population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [name: :string]
      )

    name = opts[:name] || raise "Required: --name"

    alias PopulationSimulator.Repo

    population = Repo.get_by!(PopulationSimulator.Populations.Population, name: name)

    IO.puts("\n=== Population: #{population.name} ===")
    if population.description, do: IO.puts("Description: #{population.description}")

    base_query = """
    SELECT a.{dim}, COUNT(*) as n
    FROM actors a
    JOIN actor_populations ap ON ap.actor_id = a.id
    WHERE ap.population_id = ?1
    GROUP BY 1
    ORDER BY 2 DESC
    """

    print_breakdown(Repo, "Stratum", base_query, "stratum", population.id)
    print_breakdown(Repo, "Zone", base_query, "zone", population.id)
    print_breakdown(Repo, "Employment", base_query, "employment_type", population.id)

    %{rows: [[count]]} =
      Repo.query!(
        "SELECT COUNT(*) FROM actor_populations WHERE population_id = ?1",
        [population.id]
      )

    IO.puts("\nTotal actors: #{count}\n")
  end

  defp print_breakdown(repo, label, query_template, dimension, population_id) do
    query = String.replace(query_template, "{dim}", dimension)
    %{rows: rows} = repo.query!(query, [population_id])

    IO.puts("\n--- #{label} ---")
    total = Enum.reduce(rows, 0, fn [_, n], acc -> acc + n end)

    Enum.each(rows, fn [value, n] ->
      pct = Float.round(n / max(total, 1) * 100, 1)
      IO.puts("  #{value}: #{n} (#{pct}%)")
    end)
  end
end
