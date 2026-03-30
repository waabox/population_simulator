defmodule Mix.Tasks.Sim.Population.List do
  use Mix.Task

  @shortdoc "Lists all populations with actor counts"

  def run(_args) do
    Mix.Task.run("app.start")

    alias PopulationSimulator.Repo

    %{rows: rows} =
      Repo.query!("""
      SELECT p.id, p.name, p.description, COUNT(ap.id) as actor_count, p.inserted_at
      FROM populations p
      LEFT JOIN actor_populations ap ON ap.population_id = p.id
      GROUP BY p.id, p.name, p.description, p.inserted_at
      ORDER BY p.inserted_at DESC
      """)

    if rows == [] do
      IO.puts("No populations found.")
    else
      IO.puts("\n--- Populations ---")

      Enum.each(rows, fn [id, name, description, count, inserted_at] ->
        desc = if description, do: " — #{description}", else: ""
        IO.puts("  #{name} (#{count} actors)#{desc}")
        IO.puts("    ID: #{id} | Created: #{inserted_at}")
      end)

      IO.puts("")
    end
  end
end
