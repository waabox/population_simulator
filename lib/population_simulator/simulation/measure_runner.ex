defmodule PopulationSimulator.Simulation.MeasureRunner do
  @moduledoc """
  Orchestrates running an economic measure against actors.
  Supports population filtering, mood loading, belief graphs, and persistence.
  """

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.Decision,
                              Simulation.ActorMood, Simulation.ActorBelief,
                              Simulation.BeliefGraph}
  import Ecto.Query

  @broadcast_every 10

  def run(measure_id, opts \\ []) do
    concurrency =
      Keyword.get(
        opts,
        :concurrency,
        Application.get_env(:population_simulator, :llm_concurrency, 30)
      )

    limit = Keyword.get(opts, :limit, nil)
    population_id = Keyword.get(opts, :population_id, nil)

    measure = Repo.get!(PopulationSimulator.Simulation.Measure, measure_id)

    actors = load_actors(population_id, limit)
    total = length(actors)

    IO.puts("Filtering relevant belief nodes...")
    relevant = BeliefGraph.relevant_nodes(measure.description)
    IO.puts("Relevant nodes: #{Enum.join(relevant, ", ")}")

    IO.puts("Simulation started: #{total} actors, concurrency: #{concurrency}")
    start = System.monotonic_time(:second)

    results =
      actors
      |> Task.async_stream(
        fn actor -> evaluate_actor(actor, measure, measure_id, relevant) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0, tokens: 0, errors: []}, fn
        {:ok, {:ok, _, tokens}}, acc ->
          acc = %{acc | ok: acc.ok + 1, tokens: acc.tokens + (tokens || 0)}
          maybe_broadcast(measure_id, acc, total)
          acc

        {:ok, {:error, id, reason}}, acc ->
          %{acc | error: acc.error + 1, errors: [{id, reason} | acc.errors]}

        {:exit, _}, acc ->
          %{acc | error: acc.error + 1}
      end)

    elapsed = System.monotonic_time(:second) - start
    IO.puts("Completed in #{elapsed}s — OK: #{results.ok} | Errors: #{results.error} | Tokens: #{results.tokens}")

    {:ok, results}
  end

  defp load_actors(nil, limit) do
    query = from(a in Actor, select: a)
    query = if limit, do: from(q in query, limit: ^limit), else: query
    Repo.all(query)
  end

  defp load_actors(population_id, _limit) do
    Repo.all(
      from a in Actor,
        join: ap in "actor_populations",
        on: ap.actor_id == a.id,
        where: ap.population_id == ^population_id,
        select: a
    )
  end

  defp evaluate_actor(actor, measure, measure_id, relevant_nodes) do
    current_mood = load_latest_mood(actor.id)
    baseline_mood = load_baseline_mood(actor.id)
    current_belief = load_latest_belief(actor.id)
    history = load_decision_history(actor.id, 3)

    # Apply mean reversion before building prompt (mood decays toward baseline between measures)
    reverted_mood = if current_mood && baseline_mood do
      ActorMood.apply_mean_reversion(current_mood, baseline_mood)
    else
      current_mood
    end

    filtered_belief = if current_belief, do: BeliefGraph.filter_relevant(current_belief, relevant_nodes), else: nil
    prompt = build_prompt(actor.profile, measure, reverted_mood, filtered_belief, history)

    case ClaudeClient.complete(prompt, max_tokens: 1024) do
      {:ok, decision} ->
        decision_row = Decision.from_llm_response(actor.id, measure_id, decision)

        Repo.insert_all(Decision, [decision_row],
          on_conflict: :nothing,
          conflict_target: [:actor_id, :measure_id]
        )

        if decision.mood_update do
          # Apply extreme resistance to dampen runaway values
          dampened = ActorMood.apply_extreme_resistance(decision.mood_update, reverted_mood || %{})

          mood_row = ActorMood.from_llm_response(
            actor.id,
            decision_row.id,
            measure_id,
            dampened
          )

          Repo.insert_all(ActorMood, [mood_row], on_conflict: :nothing)
        end

        if current_belief do
          updated_graph = BeliefGraph.apply_delta(current_belief, decision.belief_update)

          belief_row = ActorBelief.from_update(
            actor.id,
            decision_row.id,
            measure_id,
            updated_graph
          )

          Repo.insert_all(ActorBelief, [belief_row], on_conflict: :nothing)
        end

        {:ok, actor.id, decision.tokens_used}

      {:error, reason} ->
        {:error, actor.id, reason}
    end
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

  defp load_baseline_mood(actor_id) do
    # Baseline = the initial mood (no decision_id, no measure_id)
    Repo.one(
      from m in "actor_moods",
        where: m.actor_id == ^actor_id and is_nil(m.decision_id),
        order_by: [asc: m.inserted_at],
        limit: 1,
        select: %{
          economic_confidence: m.economic_confidence,
          government_trust: m.government_trust,
          personal_wellbeing: m.personal_wellbeing,
          social_anger: m.social_anger,
          future_outlook: m.future_outlook
        }
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

  defp maybe_broadcast(measure_id, acc, total) do
    if rem(acc.ok, @broadcast_every) == 0 do
      Phoenix.PubSub.broadcast(
        PopulationSimulator.PubSub,
        "simulation:#{measure_id}",
        {:simulation_progress, %{ok: acc.ok, error: acc.error, total: total, tokens: acc.tokens}}
      )
    end
  end

  defp load_decision_history(actor_id, n) do
    Repo.all(
      from d in "decisions",
        join: m in "measures",
        on: m.id == d.measure_id,
        where: d.actor_id == ^actor_id,
        order_by: [desc: d.inserted_at],
        limit: ^n,
        select: %{
          measure_title: m.title,
          agreement: d.agreement,
          intensity: d.intensity
        }
    )
    |> Enum.reverse()
    |> Enum.map(fn entry ->
      %{entry | agreement: entry.agreement == 1}
    end)
  end
end
