defmodule Mix.Tasks.Sim.Population.Create do
  use Mix.Task

  @shortdoc "Creates a named population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [name: :string, description: :string]
      )

    name = opts[:name] || raise "Required: --name"
    description = opts[:description]

    alias PopulationSimulator.Populations.Population

    case PopulationSimulator.Repo.insert(
           Population.changeset(%Population{}, %{name: name, description: description})
         ) do
      {:ok, population} ->
        IO.puts("Population created: #{population.name} (#{population.id})")

      {:error, changeset} ->
        IO.puts("Error: #{inspect(changeset.errors)}")
    end
  end
end
