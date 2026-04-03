defmodule PopulationSimulator.Simulation.ConsistencyChecker do
  @moduledoc """
  Post-response demographic consistency checks.
  Detects implausible mood/decision combinations given the actor's profile
  and adjusts them toward plausible ranges. Returns warnings for logging.
  """

  @doc """
  Checks response consistency against actor profile and measure context.
  Returns {adjusted_response, warnings} where warnings is a list of strings.
  measure_tags is a list of keyword strings characterizing the measure
  (e.g., ["austerity", "cut", "liberal", "stimulus", "deregulation"]).
  """
  def check(response, profile, measure_tags) do
    {response, []}
    |> check_stratum_mood_consistency(profile, measure_tags)
    |> check_orientation_intensity(profile, measure_tags)
  end

  # Rule 1: Destitute/low stratum + austerity/cut → economic_confidence should not be high
  defp check_stratum_mood_consistency({response, warnings}, profile, measure_tags) do
    stratum = profile["stratum"]
    is_vulnerable = stratum in ["destitute", "low"]
    is_negative_measure = Enum.any?(measure_tags, &(&1 in ["austerity", "cut", "recession"]))

    if is_vulnerable and is_negative_measure and response.mood_update != nil do
      {response, warnings}
      |> cap_mood_dimension("economic_confidence", 6,
          "Destitute/low stratum with austerity measure: economic_confidence capped")
      |> floor_mood_dimension("social_anger", 3,
          "Destitute/low stratum with austerity measure: social_anger floored")
    else
      {response, warnings}
    end
  end

  # Rule 2: Strong political orientation + opposing measure → extreme agreement unlikely
  defp check_orientation_intensity({response, warnings}, profile, measure_tags) do
    orientation = profile["political_orientation"]

    cond do
      not is_integer(orientation) ->
        {response, warnings}

      # Left-leaning actor strongly agreeing with liberal measures
      orientation <= 3 and Enum.any?(measure_tags, &(&1 in ["liberal", "deregulation", "privatization"])) and
          response.agreement == true and response.intensity >= 9 ->
        adjusted = %{response | intensity: min(response.intensity, 7)}
        {adjusted, ["Left-leaning actor with liberal measure: intensity capped at 7" | warnings]}

      # Right-leaning actor strongly agreeing with statist measures
      orientation >= 8 and Enum.any?(measure_tags, &(&1 in ["statist", "nationalization", "regulation"])) and
          response.agreement == true and response.intensity >= 9 ->
        adjusted = %{response | intensity: min(response.intensity, 7)}
        {adjusted, ["Right-leaning actor with statist measure: intensity capped at 7" | warnings]}

      true ->
        {response, warnings}
    end
  end

  defp cap_mood_dimension({response, warnings}, dimension, max_val, warning_msg) do
    current = response.mood_update[dimension]

    if is_number(current) and current > max_val do
      updated_mood = Map.put(response.mood_update, dimension, max_val)
      {%{response | mood_update: updated_mood}, [warning_msg | warnings]}
    else
      {response, warnings}
    end
  end

  defp floor_mood_dimension({response, warnings}, dimension, min_val, warning_msg) do
    current = response.mood_update[dimension]

    if is_number(current) and current < min_val do
      updated_mood = Map.put(response.mood_update, dimension, min_val)
      {%{response | mood_update: updated_mood}, [warning_msg | warnings]}
    else
      {response, warnings}
    end
  end
end
