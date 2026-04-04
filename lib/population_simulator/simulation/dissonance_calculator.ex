defmodule PopulationSimulator.Simulation.DissonanceCalculator do
  @moduledoc """
  Computes cognitive dissonance index (0-1) by comparing an actor's
  mood, beliefs, and decision history against their current decision.
  """

  @base_temperature 0.3
  @max_temperature 0.7
  @confrontation_threshold 0.4

  def compute(mood, decision, history) do
    mood_d = mood_dissonance(mood, decision.agreement)
    history_d = history_dissonance(decision.agreement, history)

    (mood_d + history_d)
    |> max(0.0)
    |> min(1.0)
  end

  def temperature_for(dissonance) when is_number(dissonance) do
    Float.round(@base_temperature + dissonance * (@max_temperature - @base_temperature), 2)
  end

  def temperature_for(_), do: @base_temperature

  def should_confront?(recent_dissonances) when is_list(recent_dissonances) do
    case recent_dissonances do
      [] -> false
      values ->
        avg = Enum.sum(values) / length(values)
        avg > @confrontation_threshold
    end
  end

  def accumulated_anger_bump(recent_dissonances) do
    consecutive_high =
      recent_dissonances
      |> Enum.take(3)
      |> Enum.count(&(&1 > 0.5))

    if consecutive_high >= 3, do: 0.5, else: 0.0
  end

  defp mood_dissonance(mood, agreement) do
    cond do
      agreement and mood.social_anger > 7 ->
        (mood.social_anger - 5) / 5

      agreement and mood.government_trust < 3 ->
        (5 - mood.government_trust) / 5

      not agreement and mood.economic_confidence > 7 ->
        (mood.economic_confidence - 5) / 5

      true ->
        0.0
    end
  end

  defp history_dissonance(current_agreement, history) do
    opposite_count =
      history
      |> Enum.count(fn h -> h.agreement != current_agreement end)

    cond do
      opposite_count >= 3 -> 0.5
      opposite_count >= 2 -> 0.3
      true -> 0.0
    end
  end
end
