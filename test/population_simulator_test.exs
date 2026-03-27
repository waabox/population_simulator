defmodule PopulationSimulatorTest do
  use ExUnit.Case
  doctest PopulationSimulator

  test "greets the world" do
    assert PopulationSimulator.hello() == :world
  end
end
