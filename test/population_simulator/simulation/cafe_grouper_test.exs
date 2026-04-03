defmodule PopulationSimulator.Simulation.CafeGrouperTest do
  use ExUnit.Case, async: true

  alias PopulationSimulator.Simulation.CafeGrouper

  defp make_actor(id, zone, stratum) do
    %{id: id, zone: zone, profile: %{"stratum" => stratum}}
  end

  describe "group/1" do
    test "groups actors by zone and stratum band" do
      actors = [
        make_actor("a1", "suburbs_outer", "destitute"),
        make_actor("a2", "suburbs_outer", "low"),
        make_actor("a3", "suburbs_outer", "destitute"),
        make_actor("a4", "suburbs_inner", "upper_middle"),
        make_actor("a5", "suburbs_inner", "upper"),
      ]

      groups = CafeGrouper.group(actors)

      assert length(groups) == 2
      outer_group = Enum.find(groups, fn {key, _} -> key == "suburbs_outer:low" end)
      assert outer_group != nil
      {_, outer_actors} = outer_group
      assert length(outer_actors) == 3
    end

    test "splits groups larger than 7 into sub-tables" do
      actors = for i <- 1..12, do: make_actor("a#{i}", "caba_north", "upper_middle")

      groups = CafeGrouper.group(actors)

      assert length(groups) == 2
      sizes = Enum.map(groups, fn {_, actors} -> length(actors) end) |> Enum.sort()
      assert sizes == [5, 7] or sizes == [6, 6]
    end

    test "groups of fewer than 3 are merged with nearest affinity" do
      actors = [
        make_actor("a1", "suburbs_outer", "upper"),
        make_actor("a2", "suburbs_outer", "upper"),
        make_actor("a3", "suburbs_outer", "low"),
        make_actor("a4", "suburbs_outer", "low"),
        make_actor("a5", "suburbs_outer", "low"),
        make_actor("a6", "suburbs_outer", "low"),
        make_actor("a7", "suburbs_outer", "low"),
      ]

      groups = CafeGrouper.group(actors)

      all_actors = groups |> Enum.flat_map(fn {_, a} -> a end)
      assert length(all_actors) == 7
      assert Enum.all?(groups, fn {_, a} -> length(a) >= 3 end)
    end
  end
end
