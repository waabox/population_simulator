defmodule PopulationSimulator.Simulation.MeasureRunner do
  @moduledoc """
  Orchestrates running an economic measure against actors.
  Supports population filtering, mood loading, and mood persistence.
  """

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.Decision,
                              Simulation.ActorMood}
  import Ecto.Query

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

    IO.puts("Simulation started: #{total} actors, concurrency: #{concurrency}")
    start = System.monotonic_time(:second)

    results =
      actors
      |> Task.async_stream(
        fn actor -> evaluate_actor(actor, measure, measure_id) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0, tokens: 0, errors: []}, fn
        {:ok, {:ok, _, tokens}}, acc ->
          %{acc | ok: acc.ok + 1, tokens: acc.tokens + (tokens || 0)}

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

  defp evaluate_actor(actor, measure, measure_id) do
    current_mood = load_latest_mood(actor.id)
    history = load_decision_history(actor.id, 3)

    prompt =
      if current_mood do
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(actor.profile, measure, mood_context)
      else
        PromptBuilder.build(actor.profile, measure)
      end

    case ClaudeClient.complete(prompt) do
      {:ok, decision} ->
        decision_row = Decision.from_llm_response(actor.id, measure_id, decision)

        Repo.insert_all(Decision, [decision_row],
          on_conflict: :nothing,
          conflict_target: [:actor_id, :measure_id]
        )

        if decision.mood_update do
          mood_row = ActorMood.from_llm_response(
            actor.id,
            decision_row.id,
            measure_id,
            decision.mood_update
          )

          Repo.insert_all(ActorMood, [mood_row], on_conflict: :nothing)
        end

        {:ok, actor.id, decision.tokens_used}

      {:error, reason} ->
        {:error, actor.id, reason}
    end
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
