defmodule PopulationSimulator.Simulation.ResponseValidator do
  @moduledoc """
  Validates and sanitizes LLM responses before persistence.
  Enforces structural rules (types, ranges) and semantic limits
  (narrative length, belief delta sizes, node ID format).
  """

  @max_reasoning_length 500
  @max_narrative_length 300
  @max_new_nodes 3
  @max_new_edges 5
  @max_modified_edges 5
  @node_id_pattern ~r/^[a-z][a-z0-9_]{0,29}$/

  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)

  def validate(response) when is_map(response) do
    with :ok <- validate_agreement(response.agreement),
         response <- clamp_intensity(response),
         response <- truncate_text_fields(response),
         response <- validate_mood_update(response),
         response <- validate_belief_update(response) do
      {:ok, response}
    end
  end

  defp validate_agreement(val) when is_boolean(val), do: :ok
  defp validate_agreement(_), do: {:error, "agreement must be boolean"}

  defp clamp_intensity(response) do
    %{response | intensity: clamp(response.intensity, 1, 10)}
  end

  defp truncate_text_fields(response) do
    response
    |> Map.update(:reasoning, nil, &truncate(&1, @max_reasoning_length))
    |> Map.update(:personal_impact, nil, &truncate(&1, @max_reasoning_length))
    |> Map.update(:behavior_change, nil, &truncate(&1, @max_reasoning_length))
  end

  defp validate_mood_update(%{mood_update: nil} = response), do: response
  defp validate_mood_update(%{mood_update: mood} = response) when is_map(mood) do
    clamped = Enum.reduce(@mood_dimensions, mood, fn dim, acc ->
      Map.update(acc, dim, 5, &clamp(&1, 1, 10))
    end)

    clamped = Map.update(clamped, "narrative", nil, &truncate(&1, @max_narrative_length))
    %{response | mood_update: clamped}
  end
  defp validate_mood_update(response), do: response

  defp validate_belief_update(%{belief_update: nil} = response), do: response
  defp validate_belief_update(%{belief_update: delta} = response) when is_map(delta) do
    validated = delta
    |> Map.update("new_nodes", [], &filter_and_limit_nodes/1)
    |> Map.update("new_edges", [], &Enum.take(&1, @max_new_edges))
    |> Map.update("modified_edges", [], &Enum.take(&1, @max_modified_edges))

    %{response | belief_update: validated}
  end
  defp validate_belief_update(response), do: response

  defp filter_and_limit_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.filter(fn node ->
      id = node["id"]
      is_binary(id) and Regex.match?(@node_id_pattern, id)
    end)
    |> Enum.take(@max_new_nodes)
  end
  defp filter_and_limit_nodes(_), do: []

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, min_v, _), do: min_v

  defp truncate(nil, _), do: nil
  defp truncate(text, max) when is_binary(text) and byte_size(text) > max do
    String.slice(text, 0, max)
  end
  defp truncate(text, _), do: text
end
