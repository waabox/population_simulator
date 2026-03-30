defmodule Mix.Tasks.Sim.Mood do
  use Mix.Task

  @shortdoc "Shows mood summary and evolution for a population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [population: :string, history: :boolean]
      )

    population_name = opts[:population] || raise "Required: --population"
    show_history = opts[:history] || false

    alias PopulationSimulator.{Repo, Populations.Population, Metrics.Aggregator}

    population = Repo.get_by!(Population, name: population_name)

    summary = Aggregator.mood_summary(population.id)

    IO.puts("\n=== Population: #{population.name} (#{summary["actor_count"]} actors) ===")
    IO.puts("")
    IO.puts("Current Mood Averages:")
    IO.puts("  Economic confidence:  #{summary["economic_confidence"]}/10")
    IO.puts("  Government trust:     #{summary["government_trust"]}/10")
    IO.puts("  Personal wellbeing:   #{summary["personal_wellbeing"]}/10")
    IO.puts("  Social anger:         #{summary["social_anger"]}/10")
    IO.puts("  Future outlook:       #{summary["future_outlook"]}/10")

    if show_history do
      evolution = Aggregator.mood_evolution(population.id)

      if evolution != [] do
        IO.puts("")
        IO.puts("Evolution by measure:")

        header = String.pad_trailing("Measure", 40) <>
          " | Econ | Trust | Well | Anger | Future"
        IO.puts("  #{header}")
        IO.puts("  #{String.duplicate("-", String.length(header))}")

        Enum.each(evolution, fn entry ->
          name = String.pad_trailing(String.slice(entry["measure"] || "", 0, 38), 40)

          IO.puts(
            "  #{name} | #{pad_num(entry["economic_confidence"])} | #{pad_num(entry["government_trust"])} | #{pad_num(entry["personal_wellbeing"])} | #{pad_num(entry["social_anger"])} | #{pad_num(entry["future_outlook"])}"
          )
        end)
      end
    end

    IO.puts("")
  end

  defp pad_num(nil), do: " -  "
  defp pad_num(n), do: String.pad_leading("#{n}", 4)
end
