defmodule Mix.Tasks.Sim.Calibrate do
  @moduledoc """
  Calibration loop: runs the same measure multiple times for a sample of actors
  and measures response variance. High variance indicates LLM hallucination.

  Usage:
    mix sim.calibrate --measure-id <id> --runs 5 --sample 10

  Does NOT persist results. Only reports variance statistics.
  """

  use Mix.Task

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.BeliefGraph,
                              Simulation.ResponseValidator}
  import Ecto.Query

  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      strict: [measure_id: :string, runs: :integer, sample: :integer, population: :string],
      aliases: [m: :measure_id, r: :runs, s: :sample, p: :population]
    )

    measure_id = opts[:measure_id] || raise "Missing --measure-id"
    runs = opts[:runs] || 5
    sample_size = opts[:sample] || 10

    measure = Repo.get!(PopulationSimulator.Simulation.Measure, measure_id)
    actors = load_sample(opts[:population], sample_size)

    IO.puts("=== CALIBRATION RUN ===")
    IO.puts("Measure: #{measure.title}")
    IO.puts("Actors: #{length(actors)} | Runs per actor: #{runs}")
    IO.puts("")

    relevant = BeliefGraph.relevant_nodes(measure.description)

    results = Enum.map(actors, fn actor ->
      current_mood = load_latest_mood(actor.id)
      current_belief = load_latest_belief(actor.id)
      filtered_belief = if current_belief, do: BeliefGraph.filter_relevant(current_belief, relevant), else: nil
      history = load_decision_history(actor.id, 3)

      prompt = build_prompt(actor.profile, measure, current_mood, filtered_belief, history)

      responses = Enum.map(1..runs, fn run_n ->
        IO.write("  Actor #{String.slice(actor.id, 0..7)} run #{run_n}/#{runs}...")
        case ClaudeClient.complete(prompt, max_tokens: 1024) do
          {:ok, decision} ->
            case ResponseValidator.validate(decision) do
              {:ok, validated} ->
                IO.puts(" OK")
                validated
              {:error, _} ->
                IO.puts(" validation error")
                nil
            end
          {:error, _} ->
            IO.puts(" API error")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

      {actor, analyze_variance(responses)}
    end)

    IO.puts("\n=== RESULTS ===\n")

    Enum.each(results, fn {actor, stats} ->
      stratum = actor.profile["stratum"]
      orientation = actor.profile["political_orientation"]
      IO.puts("Actor #{String.slice(actor.id, 0..7)} (#{stratum}, orient=#{orientation}):")

      IO.puts("  Agreement consistency: #{stats.agreement_consistency}% (#{stats.agreement_count}/#{stats.total_runs})")
      IO.puts("  Intensity: mean=#{stats.intensity_mean} std=#{stats.intensity_std}")

      if stats.mood_stats do
        IO.puts("  Mood variance:")
        Enum.each(@mood_dimensions, fn dim ->
          s = stats.mood_stats[dim]
          if s, do: IO.puts("    #{dim}: mean=#{s.mean} std=#{s.std}")
        end)
      end

      IO.puts("")
    end)

    all_intensity_stds = Enum.map(results, fn {_, s} -> s.intensity_std end)
    avg_intensity_std = if all_intensity_stds != [], do: Float.round(Enum.sum(all_intensity_stds) / length(all_intensity_stds), 2), else: 0.0

    all_agreement = Enum.map(results, fn {_, s} -> s.agreement_consistency end)
    avg_agreement = if all_agreement != [], do: Float.round(Enum.sum(all_agreement) / length(all_agreement), 1), else: 0.0

    IO.puts("=== SUMMARY ===")
    IO.puts("Avg agreement consistency: #{avg_agreement}%")
    IO.puts("Avg intensity std: #{avg_intensity_std}")

    if avg_intensity_std > 2.0 do
      IO.puts("\nHIGH VARIANCE: Intensity std > 2.0 suggests LLM is not reasoning consistently from profile data.")
    end

    if avg_agreement < 70.0 do
      IO.puts("\nLOW AGREEMENT CONSISTENCY: < 70% suggests the LLM flips agreement randomly.")
    end
  end

  defp analyze_variance(responses) do
    total = length(responses)

    agreements = Enum.map(responses, & &1.agreement)
    true_count = Enum.count(agreements, & &1)
    majority = if true_count > total / 2, do: true_count, else: total - true_count
    agreement_consistency = if total > 0, do: Float.round(100.0 * majority / total, 1), else: 0.0

    intensities = Enum.map(responses, & &1.intensity)
    intensity_mean = if total > 0, do: Float.round(Enum.sum(intensities) / total, 1), else: 0.0
    intensity_std = std_dev(intensities)

    mood_stats = if Enum.any?(responses, & &1.mood_update != nil) do
      Enum.reduce(@mood_dimensions, %{}, fn dim, acc ->
        values = responses
        |> Enum.map(& &1.mood_update)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&(&1[dim]))
        |> Enum.reject(&is_nil/1)

        if values != [] do
          Map.put(acc, dim, %{
            mean: Float.round(Enum.sum(values) / length(values), 1),
            std: std_dev(values)
          })
        else
          acc
        end
      end)
    else
      nil
    end

    %{
      total_runs: total,
      agreement_count: true_count,
      agreement_consistency: agreement_consistency,
      intensity_mean: intensity_mean,
      intensity_std: intensity_std,
      mood_stats: mood_stats
    }
  end

  defp std_dev([]), do: 0.0
  defp std_dev(values) do
    n = length(values)
    mean = Enum.sum(values) / n
    variance = Enum.reduce(values, 0.0, fn v, acc -> acc + (v - mean) * (v - mean) end) / n
    Float.round(:math.sqrt(variance), 2)
  end

  defp load_sample(nil, sample_size) do
    Repo.all(from a in Actor, order_by: fragment("RANDOM()"), limit: ^sample_size)
  end

  defp load_sample(population_name, sample_size) do
    pop = Repo.one!(from p in "populations", where: p.name == ^population_name, select: %{id: p.id})
    Repo.all(
      from a in Actor,
        join: ap in "actor_populations", on: ap.actor_id == a.id,
        where: ap.population_id == ^pop.id,
        order_by: fragment("RANDOM()"),
        limit: ^sample_size
    )
  end

  defp load_latest_mood(actor_id) do
    Repo.one(
      from m in "actor_moods",
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1,
        select: %{
          economic_confidence: m.economic_confidence,
          government_trust: m.government_trust,
          personal_wellbeing: m.personal_wellbeing,
          social_anger: m.social_anger,
          future_outlook: m.future_outlook,
          narrative: m.narrative
        }
    )
  end

  defp load_latest_belief(actor_id) do
    result = Repo.one(
      from b in "actor_beliefs",
        where: b.actor_id == ^actor_id,
        order_by: [desc: b.inserted_at],
        limit: 1,
        select: b.graph
    )

    case result do
      nil -> nil
      graph when is_binary(graph) -> Jason.decode!(graph)
      graph when is_map(graph) -> graph
    end
  end

  defp load_decision_history(actor_id, n) do
    Repo.all(
      from d in "decisions",
        join: m in "measures", on: m.id == d.measure_id,
        where: d.actor_id == ^actor_id,
        order_by: [desc: d.inserted_at],
        limit: ^n,
        select: %{measure_title: m.title, agreement: d.agreement, intensity: d.intensity}
    )
    |> Enum.reverse()
    |> Enum.map(fn entry -> %{entry | agreement: entry.agreement == 1} end)
  end

  defp build_prompt(profile, measure, current_mood, current_belief, history) do
    cond do
      current_mood && current_belief ->
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(profile, measure, mood_context, current_belief)
      current_mood ->
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(profile, measure, mood_context)
      true ->
        PromptBuilder.build(profile, measure)
    end
  end
end
