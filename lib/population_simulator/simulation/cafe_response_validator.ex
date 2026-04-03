defmodule PopulationSimulator.Simulation.CafeResponseValidator do
  @moduledoc """
  Validates and clamps LLM responses for café group conversations.
  Mood deltas capped at +-1.0, max 2 belief edges per actor, no emergent nodes.
  """

  @max_mood_delta 1.0
  @max_belief_edges 2
  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)

  def validate(response, expected_actor_ids) do
    with :ok <- validate_structure(response),
         :ok <- validate_actors(response["effects"], expected_actor_ids) do
      validated =
        response
        |> Map.update!("effects", fn effects -> Enum.map(effects, &validate_effect/1) end)

      {:ok, validated}
    end
  end

  defp validate_structure(response) do
    cond do
      not is_list(response["conversation"]) -> {:error, "missing conversation array"}
      not is_binary(response["conversation_summary"]) -> {:error, "missing conversation_summary"}
      not is_list(response["effects"]) -> {:error, "missing effects array"}
      true -> :ok
    end
  end

  defp validate_actors(effects, expected_ids) do
    effect_ids = Enum.map(effects, & &1["actor_id"]) |> MapSet.new()
    expected = MapSet.new(expected_ids)

    if MapSet.subset?(expected, effect_ids) do
      :ok
    else
      {:error, "effects missing for actors: #{inspect(MapSet.difference(expected, effect_ids))}"}
    end
  end

  defp validate_effect(effect) do
    effect
    |> Map.update!("mood_deltas", &clamp_mood_deltas/1)
    |> Map.update!("belief_deltas", &clamp_belief_deltas/1)
  end

  defp clamp_mood_deltas(deltas) when is_map(deltas) do
    Map.new(deltas, fn {key, val} ->
      if key in @mood_dimensions do
        {key, clamp(val, -@max_mood_delta, @max_mood_delta)}
      else
        {key, val}
      end
    end)
  end

  defp clamp_mood_deltas(_), do: %{}

  defp clamp_belief_deltas(deltas) when is_map(deltas) do
    %{
      "modified_edges" => deltas |> Map.get("modified_edges", []) |> Enum.take(@max_belief_edges),
      "new_nodes" => []
    }
  end

  defp clamp_belief_deltas(_), do: %{"modified_edges" => [], "new_nodes" => []}

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, _, _), do: 0.0
end
