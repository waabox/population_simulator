defmodule PopulationSimulator.Simulation.EventResponseValidator do
  @max_mood_impact 2.0
  @max_income_ratio 0.7
  @max_duration 6
  @mood_dimensions ~w(economic_confidence government_trust personal_wellbeing social_anger future_outlook)
  @allowed_profile_fields ~w(employment_type employment_status income_delta has_dollars usd_savings_delta has_debt housing_type tenure has_bank_account has_credit_card)

  def validate(response, current_income) do
    with :ok <- validate_structure(response) do
      validated = response
        |> Map.update!("mood_impact", &clamp_mood_impact/1)
        |> Map.update!("profile_effects", &(filter_and_clamp_profile_effects(&1, current_income)))
        |> Map.update!("duration", &clamp_duration/1)
      {:ok, validated}
    end
  end

  defp validate_structure(response) do
    cond do
      not is_binary(response["event"]) or response["event"] == "" -> {:error, "missing event description"}
      not is_map(response["mood_impact"]) -> {:error, "missing mood_impact"}
      not is_map(response["profile_effects"]) -> {:error, "missing profile_effects"}
      not is_integer(response["duration"]) -> {:error, "missing or invalid duration"}
      true -> :ok
    end
  end

  defp clamp_mood_impact(impact) do
    Map.new(impact, fn {key, val} ->
      if key in @mood_dimensions, do: {key, clamp(val, -@max_mood_impact, @max_mood_impact)}, else: {key, val}
    end)
  end

  defp filter_and_clamp_profile_effects(effects, current_income) do
    effects |> Map.take(@allowed_profile_fields) |> clamp_income_delta(current_income)
  end

  defp clamp_income_delta(effects, current_income) do
    case Map.get(effects, "income_delta") do
      nil -> effects
      delta when is_number(delta) ->
        max_delta = round(current_income * @max_income_ratio)
        Map.put(effects, "income_delta", delta |> max(-max_delta) |> min(max_delta))
      _ -> Map.delete(effects, "income_delta")
    end
  end

  defp clamp_duration(d) when is_integer(d), do: d |> max(1) |> min(@max_duration)
  defp clamp_duration(_), do: 3

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, _, _), do: 0.0
end
