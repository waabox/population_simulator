defmodule PopulationSimulator.Simulation.EventGenerator do
  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{
    ActorEvent, EventPromptBuilder, EventResponseValidator, EventDecayer, ActorMood, ActorSummary
  }
  alias PopulationSimulator.LLM.ClaudeClient
  import Ecto.Query
  require Logger

  @target_ratio 0.20

  def run(measure, actors, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 20)
    EventDecayer.tick_all()
    selected = select_vulnerable(actors)
    total = length(selected)
    Logger.info("Event generation: #{total} actors selected for measure #{measure.id}")

    results =
      selected
      |> Task.async_stream(fn actor -> generate_event(actor, measure) end,
        max_concurrency: concurrency, timeout: 45_000, on_timeout: :kill_task)
      |> Enum.reduce(%{ok: 0, error: 0}, fn
        {:ok, {:ok, _}}, acc -> %{acc | ok: acc.ok + 1}
        _, acc -> %{acc | error: acc.error + 1}
      end)

    Logger.info("Events complete: #{results.ok}/#{total} OK, #{results.error} errors")
    results
  end

  defp select_vulnerable(actors) do
    scored = Enum.map(actors, fn actor ->
      mood = load_latest_mood(actor.id)
      dissonance = load_latest_dissonance(actor.id)
      {actor, vulnerability_score(actor, mood, dissonance)}
    end)
    target_count = round(length(actors) * @target_ratio)
    scored |> Enum.sort_by(fn {_, s} -> -s end) |> Enum.take(target_count) |> Enum.map(fn {a, _} -> a end)
  end

  defp vulnerability_score(actor, mood, dissonance) do
    stratum = actor.profile["stratum"] || "middle"
    employment = actor.profile["employment_status"] || "employed"
    economic = if mood, do: (10 - mood.economic_confidence) / 10, else: 0.5
    anger = if mood, do: mood.social_anger / 10, else: 0.5
    unemployed_bonus = if employment == "unemployed", do: 0.3, else: 0.0
    poverty_bonus = if stratum in ["destitute", "low"], do: 0.2, else: 0.0
    economic + anger + unemployed_bonus + poverty_bonus + (dissonance || 0.0)
  end

  defp generate_event(actor, measure) do
    mood = load_latest_mood(actor.id)
    narrative = load_narrative(actor.id)
    intentions = load_pending_intentions(actor.id)
    current_income = actor.profile["income"] || 0

    prompt = EventPromptBuilder.build(actor.profile, measure, mood, narrative, intentions)

    case ClaudeClient.complete_raw(prompt, max_tokens: 512, temperature: 0.5, receive_timeout: 30_000) do
      {:ok, response} ->
        case EventResponseValidator.validate(response, current_income) do
          {:ok, validated} ->
            persist_event(actor, measure.id, validated)
            apply_immediate_effects(actor, validated)
            {:ok, actor.id}
          {:error, reason} ->
            Logger.warning("Event validation failed for actor #{actor.id}: #{reason}")
            {:error, reason}
        end
      {:error, reason} ->
        Logger.warning("Event LLM call failed for actor #{actor.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp persist_event(actor, measure_id, validated) do
    active_count = Repo.one(from(e in ActorEvent, where: e.actor_id == ^actor.id and e.active == true, select: count(e.id)))
    if active_count >= 3 do
      oldest = Repo.one(from(e in ActorEvent, where: e.actor_id == ^actor.id and e.active == true, order_by: [asc: e.inserted_at], limit: 1))
      if oldest, do: Repo.update_all(from(e in ActorEvent, where: e.id == ^oldest.id), set: [active: false])
    end
    row = ActorEvent.new(actor.id, measure_id, validated["event"], validated["mood_impact"], validated["profile_effects"], validated["duration"])
    Repo.insert_all(ActorEvent, [row])
  end

  defp apply_immediate_effects(actor, validated) do
    mood_impact = validated["mood_impact"]
    if map_size(mood_impact) > 0 do
      current = load_latest_mood(actor.id)
      if current do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        new_mood = %{
          id: Ecto.UUID.generate(), actor_id: actor.id, measure_id: nil, decision_id: nil,
          economic_confidence: clamp_mood(current.economic_confidence + Map.get(mood_impact, "economic_confidence", 0)),
          government_trust: clamp_mood(current.government_trust + Map.get(mood_impact, "government_trust", 0)),
          personal_wellbeing: clamp_mood(current.personal_wellbeing + Map.get(mood_impact, "personal_wellbeing", 0)),
          social_anger: clamp_mood(current.social_anger + Map.get(mood_impact, "social_anger", 0)),
          future_outlook: clamp_mood(current.future_outlook + Map.get(mood_impact, "future_outlook", 0)),
          narrative: current.narrative, inserted_at: now, updated_at: now
        }
        Repo.insert_all(ActorMood, [new_mood])
      end
    end

    profile_effects = validated["profile_effects"]
    if map_size(profile_effects) > 0 do
      current_profile = actor.profile
      income = current_profile["income"] || 0
      updated_profile = Enum.reduce(profile_effects, current_profile, fn
        {"income_delta", delta}, p when is_number(delta) -> Map.put(p, "income", max(round(income + delta), 0))
        {"usd_savings_delta", delta}, p when is_number(delta) ->
          current_usd = p["usd_savings"] || 0
          Map.put(p, "usd_savings", max(round(current_usd + delta), 0))
        {key, value}, p -> Map.put(p, key, value)
      end)
      Repo.update_all(from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor.id), set: [profile: updated_profile])
    end
  end

  defp load_latest_mood(actor_id) do
    Repo.one(from(m in ActorMood, where: m.actor_id == ^actor_id, order_by: [desc: m.inserted_at], limit: 1))
  end

  defp load_latest_dissonance(actor_id) do
    Repo.one(from(d in PopulationSimulator.Simulation.Decision,
      where: d.actor_id == ^actor_id and not is_nil(d.dissonance),
      order_by: [desc: d.inserted_at], limit: 1, select: d.dissonance))
  end

  defp load_narrative(actor_id) do
    Repo.one(from(s in ActorSummary, where: s.actor_id == ^actor_id, order_by: [desc: s.version], limit: 1, select: s.narrative))
  end

  defp load_pending_intentions(_actor_id), do: []

  defp clamp_mood(val), do: val |> round() |> max(1) |> min(10)
end
