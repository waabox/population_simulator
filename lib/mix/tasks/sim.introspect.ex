defmodule Mix.Tasks.Sim.Introspect do
  use Mix.Task

  alias PopulationSimulator.Repo
  import Ecto.Query

  @shortdoc "Run or query actor introspection"

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [actor_id: :string, population: :string, run: :boolean]
      )

    cond do
      parsed[:run] && parsed[:population] ->
        run_introspection(parsed[:population])

      actor_id = parsed[:actor_id] ->
        show_actor_introspection(actor_id)

      population = parsed[:population] ->
        show_population_summary(population)

      true ->
        IO.puts("Usage:")
        IO.puts("  mix sim.introspect --actor-id <id>")
        IO.puts("  mix sim.introspect --population \"Name\"")
        IO.puts("  mix sim.introspect --run --population \"Name\"")
    end
  end

  defp show_actor_introspection(actor_id) do
    summaries =
      Repo.all(
        from(s in PopulationSimulator.Simulation.ActorSummary,
          where: s.actor_id == ^actor_id,
          order_by: [asc: s.version]
        )
      )

    if summaries == [] do
      IO.puts("No introspection data for actor #{actor_id}")
    else
      Enum.each(summaries, fn s ->
        observations = Jason.decode!(s.self_observations)
        IO.puts("\n=== Versión #{s.version} (#{s.inserted_at}) ===")
        IO.puts(s.narrative)
        IO.puts("\nObservaciones:")
        Enum.each(observations, fn o -> IO.puts("  - #{o}") end)
      end)
    end
  end

  defp show_population_summary(population_name) do
    actor_ids =
      Repo.all(
        from(ap in PopulationSimulator.Populations.ActorPopulation,
          join: p in PopulationSimulator.Populations.Population, on: ap.population_id == p.id,
          where: p.name == ^population_name,
          select: ap.actor_id
        )
      )

    count =
      Repo.one(
        from(s in PopulationSimulator.Simulation.ActorSummary,
          where: s.actor_id in ^actor_ids,
          select: count(fragment("DISTINCT ?", s.actor_id))
        )
      )

    IO.puts("Actors with introspection: #{count}/#{length(actor_ids)}")

    if count > 0 do
      max_version =
        Repo.one(
          from(s in PopulationSimulator.Simulation.ActorSummary,
            where: s.actor_id in ^actor_ids,
            select: max(s.version)
          )
        )
      IO.puts("Max introspection version: #{max_version}")
    end
  end

  defp run_introspection(population_name) do
    actors =
      Repo.all(
        from(a in PopulationSimulator.Actors.Actor,
          join: ap in PopulationSimulator.Populations.ActorPopulation, on: ap.actor_id == a.id,
          join: p in PopulationSimulator.Populations.Population, on: ap.population_id == p.id,
          where: p.name == ^population_name
        )
      )

    latest_measure =
      Repo.one(
        from(m in PopulationSimulator.Simulation.Measure,
          order_by: [desc: m.inserted_at],
          limit: 1
        )
      )

    if latest_measure do
      results = PopulationSimulator.Simulation.IntrospectionRunner.run(latest_measure, actors)
      IO.puts("Introspection: #{results.ok} OK, #{results.error} errors")
    else
      IO.puts("No measures found. Run a simulation first.")
    end
  end
end
