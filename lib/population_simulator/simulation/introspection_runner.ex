defmodule PopulationSimulator.Simulation.IntrospectionRunner do
  @moduledoc """
  Orchestrates introspection round: each actor reflects on recent experiences
  and generates/updates their autobiographical narrative.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{
    IntrospectionPromptBuilder,
    ActorSummary,
    ActorMood
  }
  alias PopulationSimulator.LLM.ClaudeClient

  import Ecto.Query
  require Logger

  def run(measure, actors, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 30)
    total = length(actors)

    Logger.info("Introspection round: #{total} actors for measure #{measure.id}")

    results =
      actors
      |> Task.async_stream(
        fn actor -> introspect_actor(actor, measure) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0}, fn
        {:ok, {:ok, _}}, acc -> %{acc | ok: acc.ok + 1}
        _, acc -> %{acc | error: acc.error + 1}
      end)

    Logger.info("Introspection complete: #{results.ok}/#{total} OK, #{results.error} errors")
    results
  end

  defp introspect_actor(actor, measure) do
    previous = load_latest_summary(actor.id)
    previous_narrative = if previous, do: previous.narrative, else: nil
    version = if previous, do: previous.version + 1, else: 1

    decisions = load_recent_decisions(actor.id, 3)
    cafe_summaries = load_recent_cafe_summaries(actor.id, 3)
    current_mood = load_latest_mood(actor.id)

    prompt = IntrospectionPromptBuilder.build(
      actor.profile,
      previous_narrative,
      decisions,
      cafe_summaries,
      current_mood
    )

    case ClaudeClient.complete(prompt, max_tokens: 1024, temperature: 0.3) do
      {:ok, response} ->
        narrative = response["narrative"] || ""
        observations = response["self_observations"] || []

        trimmed_narrative = narrative |> String.split() |> Enum.take(200) |> Enum.join(" ")
        trimmed_observations = Enum.take(observations, 5)

        row = ActorSummary.new(actor.id, measure.id, trimmed_narrative, trimmed_observations, version)
        Repo.insert_all(ActorSummary, [row])
        {:ok, actor.id}

      {:error, reason} ->
        Logger.warning("Introspection failed for actor #{actor.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_latest_summary(actor_id) do
    Repo.one(
      from(s in ActorSummary,
        where: s.actor_id == ^actor_id,
        order_by: [desc: s.version],
        limit: 1
      )
    )
  end

  defp load_recent_decisions(actor_id, limit) do
    Repo.all(
      from(d in PopulationSimulator.Simulation.Decision,
        join: m in PopulationSimulator.Simulation.Measure, on: d.measure_id == m.id,
        where: d.actor_id == ^actor_id,
        order_by: [desc: d.inserted_at],
        limit: ^limit,
        select: %{
          agreement: d.agreement,
          intensity: d.intensity,
          reasoning: d.reasoning,
          measure_title: m.title
        }
      )
    )
    |> Enum.reverse()
  end

  defp load_recent_cafe_summaries(actor_id, limit) do
    Repo.all(
      from(cs in PopulationSimulator.Simulation.CafeSession,
        join: ce in PopulationSimulator.Simulation.CafeEffect,
          on: ce.cafe_session_id == cs.id,
        where: ce.actor_id == ^actor_id,
        order_by: [desc: cs.inserted_at],
        limit: ^limit,
        select: cs.conversation_summary
      )
    )
    |> Enum.reverse()
  end

  defp load_latest_mood(actor_id) do
    Repo.one(
      from(m in ActorMood,
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    ) || %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
  end
end
