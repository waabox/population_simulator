defmodule PopulationSimulator.Simulation.CafeRunner do
  @moduledoc """
  Orchestrates café round after a measure: groups actors, dispatches LLM calls,
  persists dialogues and applies mood/belief effects.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{
    CafeGrouper,
    CafePromptBuilder,
    CafeResponseValidator,
    CafeSession,
    CafeEffect,
    ActorMood,
    ActorBelief,
    BeliefGraph
  }
  alias PopulationSimulator.LLM.ClaudeClient

  require Logger

  def run(measure, actors, decisions, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 15)

    participants = build_participants(actors, decisions)
    tables = CafeGrouper.group(participants)
    total = length(tables)

    Logger.info("Café round: #{total} tables for measure #{measure.id}")

    results =
      tables
      |> Task.async_stream(
        fn {group_key, table_actors} ->
          process_table(measure, group_key, table_actors)
        end,
        max_concurrency: concurrency,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0}, fn
        {:ok, {:ok, _}}, acc -> %{acc | ok: acc.ok + 1}
        _, acc -> %{acc | error: acc.error + 1}
      end)

    Logger.info("Café complete: #{results.ok}/#{total} tables OK, #{results.error} errors")
    results
  end

  defp build_participants(actors, decisions) do
    decision_map = Map.new(decisions, fn d -> {d.actor_id, d} end)

    Enum.flat_map(actors, fn actor ->
      case Map.get(decision_map, actor.id) do
        nil -> []
        decision ->
          mood = load_latest_mood(actor.id)
          [%{
            actor_id: actor.id,
            zone: actor.zone,
            profile: actor.profile,
            decision: decision,
            mood: mood
          }]
      end
    end)
  end

  defp load_latest_mood(actor_id) do
    import Ecto.Query
    Repo.one(
      from(m in ActorMood,
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    ) || %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
  end

  defp process_table(measure, group_key, table_actors) do
    {prompt, names} = CafePromptBuilder.build(measure, table_actors)
    actor_ids = Enum.map(table_actors, & &1.actor_id)

    case ClaudeClient.complete_raw(prompt, max_tokens: 4096, temperature: 0.3, receive_timeout: 120_000) do
      {:ok, response} ->
        case CafeResponseValidator.validate(response, actor_ids) do
          {:ok, validated} ->
            persist_cafe(measure.id, group_key, actor_ids, names, validated, table_actors)
            {:ok, group_key}

          {:error, reason} ->
            Logger.warning("Café validation failed for #{group_key}: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Café LLM call failed for #{group_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp persist_cafe(measure_id, group_key, actor_ids, names, validated, table_actors) do
    session_row = CafeSession.new(
      measure_id,
      group_key,
      actor_ids,
      names,
      validated["conversation"],
      validated["conversation_summary"]
    )

    Repo.insert_all(CafeSession, [session_row])

    Enum.each(validated["effects"], fn effect ->
      effect_row = CafeEffect.new(
        session_row.id,
        effect["actor_id"],
        effect["mood_deltas"],
        effect["belief_deltas"]
      )
      Repo.insert_all(CafeEffect, [effect_row])

      apply_mood_deltas(effect["actor_id"], measure_id, effect["mood_deltas"])
      apply_belief_deltas(effect["actor_id"], measure_id, effect["belief_deltas"], table_actors)
    end)
  end

  defp apply_mood_deltas(actor_id, measure_id, deltas) when map_size(deltas) > 0 do
    import Ecto.Query

    current = Repo.one(
      from(m in ActorMood,
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    )

    if current do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      new_mood = %{
        id: Ecto.UUID.generate(),
        actor_id: actor_id,
        measure_id: measure_id,
        decision_id: nil,
        economic_confidence: clamp_mood(current.economic_confidence + Map.get(deltas, "economic_confidence", 0)),
        government_trust: clamp_mood(current.government_trust + Map.get(deltas, "government_trust", 0)),
        personal_wellbeing: clamp_mood(current.personal_wellbeing + Map.get(deltas, "personal_wellbeing", 0)),
        social_anger: clamp_mood(current.social_anger + Map.get(deltas, "social_anger", 0)),
        future_outlook: clamp_mood(current.future_outlook + Map.get(deltas, "future_outlook", 0)),
        narrative: current.narrative,
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(ActorMood, [new_mood])
    end
  end

  defp apply_mood_deltas(_, _, _), do: :ok

  defp apply_belief_deltas(actor_id, measure_id, %{"modified_edges" => edges}, _table_actors)
       when length(edges) > 0 do
    import Ecto.Query

    current = Repo.one(
      from(b in ActorBelief,
        where: b.actor_id == ^actor_id,
        order_by: [desc: b.inserted_at],
        limit: 1
      )
    )

    if current do
      delta = %{"modified_edges" => edges, "new_edges" => [], "new_nodes" => [], "removed_edges" => []}
      new_graph = BeliefGraph.apply_delta(current.graph, delta)
      dampened = BeliefGraph.apply_edge_damping(new_graph, current.graph, 0.4)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      new_belief = %{
        id: Ecto.UUID.generate(),
        actor_id: actor_id,
        measure_id: measure_id,
        decision_id: nil,
        graph: dampened,
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(ActorBelief, [new_belief])
    end
  end

  defp apply_belief_deltas(_, _, _, _), do: :ok

  defp clamp_mood(val), do: val |> round() |> max(1) |> min(10)
end
