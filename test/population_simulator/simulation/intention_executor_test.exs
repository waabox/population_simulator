defmodule PopulationSimulator.Simulation.IntentionExecutorTest do
  use ExUnit.Case, async: true
  alias PopulationSimulator.Simulation.IntentionExecutor

  describe "validate_profile_effects/2" do
    test "passes through allowed fields" do
      effects = %{"employment_type" => "formal_employee", "income_delta" => 100_000}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      assert result["employment_type"] == "formal_employee"
      assert result["income_delta"] == 100_000
    end
    test "strips unrecognized fields" do
      effects = %{"employment_type" => "formal", "superpower" => "fly"}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      refute Map.has_key?(result, "superpower")
    end
    test "clamps income_delta to +-50% of current income" do
      effects = %{"income_delta" => 400_000}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      assert result["income_delta"] == 250_000
    end
    test "clamps negative income_delta" do
      effects = %{"income_delta" => -400_000}
      result = IntentionExecutor.validate_profile_effects(effects, 500_000)
      assert result["income_delta"] == -250_000
    end
  end
end
