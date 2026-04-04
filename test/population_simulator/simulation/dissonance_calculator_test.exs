defmodule PopulationSimulator.Simulation.DissonanceCalculatorTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.DissonanceCalculator

  describe "compute/3" do
    test "high social_anger + agreement = high dissonance" do
      mood = %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 9, future_outlook: 5}
      decision = %{agreement: true, intensity: 6}
      history = []
      result = DissonanceCalculator.compute(mood, decision, history)
      assert result >= 0.7
      assert result <= 1.0
    end

    test "low government_trust + agreement = dissonance" do
      mood = %{economic_confidence: 5, government_trust: 2, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: true, intensity: 5}
      history = []
      result = DissonanceCalculator.compute(mood, decision, history)
      assert result >= 0.5
    end

    test "high economic_confidence + rejection = dissonance" do
      mood = %{economic_confidence: 9, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: false, intensity: 5}
      history = []
      result = DissonanceCalculator.compute(mood, decision, history)
      assert result >= 0.7
    end

    test "consistent mood + decision = low dissonance" do
      mood = %{economic_confidence: 3, government_trust: 3, personal_wellbeing: 3, social_anger: 8, future_outlook: 3}
      decision = %{agreement: false, intensity: 7}
      history = []
      result = DissonanceCalculator.compute(mood, decision, history)
      assert result <= 0.1
    end

    test "history contradiction adds dissonance" do
      mood = %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: true, intensity: 5}
      history = [
        %{agreement: false, intensity: 6},
        %{agreement: false, intensity: 7},
        %{agreement: false, intensity: 5}
      ]
      result = DissonanceCalculator.compute(mood, decision, history)
      assert result >= 0.4
    end

    test "two opposing history entries = moderate dissonance" do
      mood = %{economic_confidence: 5, government_trust: 5, personal_wellbeing: 5, social_anger: 5, future_outlook: 5}
      decision = %{agreement: true, intensity: 5}
      history = [
        %{agreement: true, intensity: 5},
        %{agreement: false, intensity: 6},
        %{agreement: false, intensity: 7}
      ]
      result = DissonanceCalculator.compute(mood, decision, history)
      assert result >= 0.2
      assert result <= 0.4
    end

    test "result is always clamped between 0 and 1" do
      mood = %{economic_confidence: 10, government_trust: 1, personal_wellbeing: 1, social_anger: 10, future_outlook: 1}
      decision = %{agreement: true, intensity: 10}
      history = [
        %{agreement: false, intensity: 10},
        %{agreement: false, intensity: 10},
        %{agreement: false, intensity: 10}
      ]
      result = DissonanceCalculator.compute(mood, decision, history)
      assert result >= 0.0
      assert result <= 1.0
    end
  end

  describe "temperature_for/1" do
    test "zero dissonance = base temperature 0.3" do
      assert DissonanceCalculator.temperature_for(0.0) == 0.3
    end

    test "max dissonance = temperature 0.7" do
      assert DissonanceCalculator.temperature_for(1.0) == 0.7
    end

    test "mid dissonance = proportional temperature" do
      result = DissonanceCalculator.temperature_for(0.5)
      assert_in_delta result, 0.5, 0.01
    end
  end

  describe "should_confront?/1" do
    test "returns true when average dissonance > 0.4" do
      assert DissonanceCalculator.should_confront?([0.6, 0.5, 0.3]) == true
    end

    test "returns false when average dissonance <= 0.4" do
      assert DissonanceCalculator.should_confront?([0.3, 0.2, 0.1]) == false
    end

    test "returns false for empty list" do
      assert DissonanceCalculator.should_confront?([]) == false
    end
  end
end
