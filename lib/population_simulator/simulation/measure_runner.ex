defmodule PopulationSimulator.Simulation.MeasureRunner do
  @moduledoc """
  Orchestrates running an economic measure against actors.
  Supports population filtering, mood loading, belief graphs, and persistence.
  """

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.Decision,
                              Simulation.ActorMood, Simulation.ActorBelief,
                              Simulation.BeliefGraph}
  alias PopulationSimulator.Simulation.{ResponseValidator, ConsistencyChecker, DissonanceCalculator}
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

    validate_chronological_order!(measure, population_id)

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
        fn actor -> evaluate_actor(actor, measure, measure_id, relevant, measure.measure_date) end,
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

  defp validate_chronological_order!(measure, _population_id) do
    if measure.measure_date do
      last_date = Repo.one(
        from m in "measures",
          join: d in "decisions",
          on: d.measure_id == m.id,
          where: not is_nil(m.measure_date) and m.id != ^measure.id,
          order_by: [desc: m.measure_date],
          limit: 1,
          select: m.measure_date
      )

      if last_date do
        last = case last_date do
          d when is_binary(d) -> Date.from_iso8601!(d)
          d -> d
        end

        if Date.compare(measure.measure_date, last) == :lt do
          raise "Measure date #{measure.measure_date} is before the last measure (#{last}). Measures must be chronological. Delete later measures first if you want to redo the timeline."
        end
      end
    end
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

  defp evaluate_actor(actor, measure, measure_id, relevant_nodes, measure_date) do
    current_mood = load_latest_mood(actor.id)
    baseline_mood = load_baseline_mood(actor.id)
    current_belief = load_latest_belief(actor.id)
    history = load_decision_history(actor.id, 3)

    # Apply mean reversion before building prompt (mood decays toward baseline between measures)
    # Decay rate depends on days between last measure and this measure's date
    reverted_mood = if current_mood && baseline_mood do
      days = days_since_last_mood(actor.id, measure_date)
      ActorMood.apply_mean_reversion(current_mood, baseline_mood, days)
    else
      current_mood
    end

    filtered_belief = if current_belief, do: BeliefGraph.filter_relevant(current_belief, relevant_nodes), else: nil
    consciousness = PopulationSimulator.Simulation.ConsciousnessLoader.load(actor.id)
    prompt = build_prompt(actor.profile, measure, reverted_mood, filtered_belief, history, consciousness)

    recent_dissonances = load_recent_dissonances(actor.id, 3)
    latest_dissonance = List.first(recent_dissonances) || 0.0
    temperature = DissonanceCalculator.temperature_for(latest_dissonance)

    case ClaudeClient.complete(prompt, max_tokens: 1024, temperature: temperature) do
      {:ok, decision} ->
        measure_tags = extract_measure_tags(measure.description)

        # Layer 1: Schema validation & rule constraints
        case ResponseValidator.validate(decision) do
          {:ok, validated} ->
            # Layer 4: Consistency checks
            {checked, consistency_warnings} = ConsistencyChecker.check(validated, actor.profile, measure_tags)

            if consistency_warnings != [] do
              IO.puts("  [consistency] Actor #{String.slice(actor.id, 0..7)}: #{Enum.join(consistency_warnings, "; ")}")
            end

            current_mood_for_dissonance = if current_mood do
              %{
                economic_confidence: current_mood.economic_confidence,
                government_trust: current_mood.government_trust,
                personal_wellbeing: current_mood.personal_wellbeing,
                social_anger: current_mood.social_anger,
                future_outlook: current_mood.future_outlook
              }
            else
              %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
            end

            dissonance = DissonanceCalculator.compute(current_mood_for_dissonance, checked, history)
            anger_bump = DissonanceCalculator.accumulated_anger_bump([dissonance | recent_dissonances])

            decision_row = Decision.from_llm_response(actor.id, measure_id, checked)
            decision_row = Map.put(decision_row, :dissonance, dissonance)

            Repo.insert_all(Decision, [decision_row],
              on_conflict: :nothing,
              conflict_target: [:actor_id, :measure_id]
            )

            if checked.mood_update do
              dampened = ActorMood.apply_extreme_resistance(checked.mood_update, reverted_mood || %{})

              dampened = if anger_bump > 0 do
                Map.update(dampened, :social_anger, dampened.social_anger, fn v -> min(v + round(anger_bump), 10) end)
              else
                dampened
              end

              mood_row = ActorMood.from_llm_response(
                actor.id,
                decision_row.id,
                measure_id,
                dampened
              )

              Repo.insert_all(ActorMood, [mood_row], on_conflict: :nothing)
            end

            if current_belief do
              # Layer 2: Apply delta with bounds (node cap + edge limit already in apply_delta)
              updated_graph = BeliefGraph.apply_delta(current_belief, checked.belief_update)

              # Layer 2: Edge weight damping (max 0.4 change per measure)
              updated_graph = BeliefGraph.apply_edge_damping(updated_graph, current_belief, 0.4)

              # Layer 2: Decay unreinforced emergent nodes
              measure_count = count_actor_measures(actor.id)
              updated_graph = BeliefGraph.decay_emergent_nodes(updated_graph, measure_count, 3)

              belief_row = ActorBelief.from_update(
                actor.id,
                decision_row.id,
                measure_id,
                updated_graph
              )

              Repo.insert_all(ActorBelief, [belief_row], on_conflict: :nothing)
            end

            {:ok, actor.id, checked.tokens_used}

          {:error, reason} ->
            {:error, actor.id, "Validation failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, actor.id, reason}
    end
  end

  defp build_prompt(profile, measure, current_mood, current_belief, history, consciousness) do
    cond do
      current_mood && current_belief && consciousness ->
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(profile, measure, mood_context, current_belief, consciousness)

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

  defp days_since_last_mood(actor_id, measure_date) do
    last_measure_date = Repo.one(
      from m in "actor_moods",
        join: ms in "measures",
        on: ms.id == m.measure_id,
        where: m.actor_id == ^actor_id and not is_nil(m.decision_id),
        order_by: [desc: m.inserted_at],
        limit: 1,
        select: ms.measure_date
    )

    case {last_measure_date, measure_date} do
      {nil, _} -> nil
      {_, nil} -> nil
      {prev_str, current_date} when is_binary(prev_str) ->
        case Date.from_iso8601(prev_str) do
          {:ok, prev_date} -> Date.diff(current_date, prev_date)
          _ -> nil
        end
      {prev_date, current_date} ->
        Date.diff(current_date, prev_date)
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

  defp extract_measure_tags(description) when is_binary(description) do
    text = String.downcase(description)
    tags = []
    tags = if String.contains?(text, ["recorte", "ajuste", "reducción", "elimina"]), do: ["cut" | tags], else: tags
    tags = if String.contains?(text, ["austeridad", "deficit"]), do: ["austerity" | tags], else: tags
    tags = if String.contains?(text, ["liberal", "desregul", "libre mercado"]), do: ["liberal" | tags], else: tags
    tags = if String.contains?(text, ["desregul", "privatiz"]), do: ["deregulation" | tags], else: tags
    tags = if String.contains?(text, ["privatiz"]), do: ["privatization" | tags], else: tags
    tags = if String.contains?(text, ["estatal", "nacional", "estatis"]), do: ["statist" | tags], else: tags
    tags = if String.contains?(text, ["estimul", "subsidio", "aumento", "bono"]), do: ["stimulus" | tags], else: tags
    tags = if String.contains?(text, ["regulac", "control"]), do: ["regulation" | tags], else: tags
    tags
  end
  defp extract_measure_tags(_), do: []

  defp count_actor_measures(actor_id) do
    Repo.one(
      from d in "decisions",
        where: d.actor_id == ^actor_id,
        select: count(d.id)
    ) || 0
  end

  defp load_recent_dissonances(actor_id, limit) do
    Repo.all(
      from(d in Decision,
        where: d.actor_id == ^actor_id and not is_nil(d.dissonance),
        order_by: [desc: d.inserted_at],
        limit: ^limit,
        select: d.dissonance
      )
    )
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
