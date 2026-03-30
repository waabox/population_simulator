defmodule Mix.Tasks.Sim.Beliefs do
  use Mix.Task

  @shortdoc "Shows belief graph summary for a population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [population: :string, edge: :string, history: :boolean, emergent: :boolean]
      )

    population_name = opts[:population] || raise "Required: --population"

    alias PopulationSimulator.{Repo, Populations.Population, Metrics.Aggregator}

    population = Repo.get_by!(Population, name: population_name)

    cond do
      opts[:emergent] ->
        show_emergent(population)

      opts[:edge] && opts[:history] ->
        show_edge_history(population, opts[:edge])

      true ->
        show_summary(population)
    end
  end

  defp show_summary(population) do
    alias PopulationSimulator.Metrics.Aggregator

    beliefs = Aggregator.belief_summary(population.id)

    causal = Enum.filter(beliefs, &(&1["type"] == "causal"))
    emotional = Enum.filter(beliefs, &(&1["type"] == "emotional"))

    IO.puts("\n=== Beliefs: #{population.name} ===\n")

    IO.puts("Top causal beliefs (avg weight):")
    causal
    |> Enum.take(10)
    |> Enum.each(fn b ->
      divergence = if b["std"] > 0.25, do: "  ** high divergence", else: ""
      IO.puts("  #{pad_edge(b["from"], b["to"])} : #{format_weight(b["avg_weight"])} (std: #{b["std"]})#{divergence}")
    end)

    IO.puts("\nTop emotional reactions:")
    emotional
    |> Enum.take(10)
    |> Enum.each(fn b ->
      divergence = if b["std"] > 0.25, do: "  ** high divergence", else: ""
      IO.puts("  #{pad_edge(b["from"], b["to"])} : #{format_weight(b["avg_weight"])} (std: #{b["std"]})#{divergence}")
    end)

    IO.puts("")
  end

  defp show_emergent(population) do
    alias PopulationSimulator.Metrics.Aggregator

    nodes = Aggregator.emergent_nodes(population.id)

    IO.puts("\n=== Emergent Nodes: #{population.name} ===\n")

    if nodes == [] do
      IO.puts("No emergent nodes found.")
    else
      Enum.each(nodes, fn n ->
        IO.puts("  #{n["node_id"]} (#{n["actor_count"]} actors) — added after \"#{n["added_at"]}\"")
      end)
    end

    IO.puts("")
  end

  defp show_edge_history(population, edge_str) do
    alias PopulationSimulator.Metrics.Aggregator

    [from, to] = String.split(edge_str, "->")

    evolution = Aggregator.belief_evolution(population.id)

    matching = Enum.filter(evolution, fn e ->
      e["from"] == from && e["to"] == to
    end)

    IO.puts("\n=== Edge History: #{from} -> #{to} (#{population.name}) ===\n")

    if matching == [] do
      IO.puts("No data found for this edge.")
    else
      Enum.each(matching, fn e ->
        IO.puts("  #{String.pad_trailing(e["measure"] || "", 40)} | #{format_weight(e["avg_weight"])}")
      end)
    end

    IO.puts("")
  end

  defp pad_edge(from, to) do
    String.pad_trailing("#{from} -> #{to}", 30)
  end

  defp format_weight(nil), do: " -   "
  defp format_weight(w) when w >= 0, do: "+#{w}"
  defp format_weight(w), do: "#{w}"
end
