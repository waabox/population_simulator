defmodule PopulationSimulator.Simulation.TheoryOfMindBuilder do
  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorPerception

  @mood_labels [
    {7, "esperanzados"}, {6, "cautelosamente optimistas"}, {5, "indiferentes"},
    {4, "preocupados"}, {3, "frustrados"}, {0, "enojados"}
  ]

  def process_cafe(cafe_session_id, measure_id, table_actors, validated_response) do
    group_mood = compute_group_mood(table_actors, validated_response)
    referents = extract_referents(validated_response)
    actor_ids = Enum.map(table_actors, & &1.actor_id)

    Enum.each(actor_ids, fn actor_id ->
      referent = Enum.find(referents, fn r -> r["perceived_by"] == actor_id end)
      referent_id = if referent, do: referent["actor_id"], else: nil
      referent_influence = if referent, do: referent["influence"], else: nil
      valid_referent_id = if referent_id in actor_ids, do: referent_id, else: nil

      row = ActorPerception.new(actor_id, measure_id, cafe_session_id, group_mood, valid_referent_id, referent_influence)
      Repo.insert_all(ActorPerception, [row])
    end)
  end

  defp compute_group_mood(table_actors, validated) do
    approved = Enum.count(table_actors, fn a -> a.decision.agreement end)
    total = length(table_actors)
    agreement_ratio = if total > 0, do: Float.round(approved / total, 2), else: 0.0

    avg_anger = table_actors
      |> Enum.map(fn a -> a.mood.social_anger end)
      |> then(fn vals -> Enum.sum(vals) / max(length(vals), 1) end)

    mood_label = label_for_anger(avg_anger)

    effects = validated["effects"] || []
    dominant = dominant_emotion(effects)

    %{mood: mood_label, agreement_ratio: agreement_ratio, dominant_emotion: dominant}
  end

  defp label_for_anger(avg) do
    @mood_labels
    |> Enum.find(fn {threshold, _} -> avg >= threshold end)
    |> case do
      {_, label} -> label
      nil -> "neutros"
    end
  end

  defp dominant_emotion(effects) do
    effects
    |> Enum.flat_map(fn e -> (e["mood_deltas"] || %{}) |> Enum.map(fn {dim, val} -> {dim, abs(val)} end) end)
    |> Enum.group_by(fn {dim, _} -> dim end, fn {_, val} -> val end)
    |> Enum.map(fn {dim, vals} -> {dim, Enum.sum(vals)} end)
    |> Enum.max_by(fn {_, total} -> total end, fn -> {"social_anger", 0} end)
    |> elem(0)
  end

  defp extract_referents(validated), do: validated["referents"] || []
end
