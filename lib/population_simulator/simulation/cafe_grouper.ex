defmodule PopulationSimulator.Simulation.CafeGrouper do
  @moduledoc """
  Groups actors into café tables by zone + stratum affinity.
  Tables are 5-7 actors. Groups < 3 are merged with nearest band.
  """

  alias PopulationSimulator.Simulation.AffinityTracker

  @min_table_size 3
  @max_table_size 7

  @stratum_bands %{
    "destitute" => "low",
    "low" => "low",
    "lower_middle" => "middle",
    "middle" => "middle",
    "upper_middle" => "upper",
    "upper" => "upper"
  }

  def group(actors) do
    actors
    |> Enum.group_by(fn actor -> group_key(actor) end)
    |> merge_small_groups()
    |> Enum.flat_map(fn {key, actors} -> split_large_group(key, actors) end)
  end

  defp group_key(actor) do
    zone = to_string(actor.zone)
    stratum = actor.profile["stratum"] || "middle"
    band = Map.get(@stratum_bands, stratum, "middle")
    "#{zone}:#{band}"
  end

  defp merge_small_groups(groups) do
    {small, ok} = Enum.split_with(groups, fn {_, actors} -> length(actors) < @min_table_size end)

    Enum.reduce(small, ok, fn {key, actors}, acc ->
      zone = key |> String.split(":") |> List.first()
      best_match = Enum.find_index(acc, fn {k, _} -> String.starts_with?(k, zone <> ":") end)

      if best_match do
        {match_key, match_actors} = Enum.at(acc, best_match)
        List.replace_at(acc, best_match, {match_key, match_actors ++ actors})
      else
        if length(actors) >= 1, do: acc ++ [{key, actors}], else: acc
      end
    end)
  end

  defp split_large_group(key, actors) when length(actors) <= @max_table_size do
    [{key, actors}]
  end

  defp split_large_group(key, actors) do
    actor_ids = Enum.map(actors, fn a -> Map.get(a, :id, Map.get(a, :actor_id)) end)
    bonds = AffinityTracker.load_bonds_between(actor_ids)
    _actor_map = Map.new(actors, fn a -> {Map.get(a, :id, Map.get(a, :actor_id)), a} end)

    if bonds == [] do
      actors
      |> Enum.shuffle()
      |> Enum.chunk_every(@max_table_size)
      |> Enum.with_index()
      |> Enum.map(fn {chunk, idx} ->
        sub_key = if idx == 0, do: key, else: "#{key}:#{idx}"
        {sub_key, chunk}
      end)
    else
      bonded_ids = bonds |> Enum.flat_map(fn {a, b, _} -> [a, b] end) |> MapSet.new()
      bonded = Enum.filter(actors, fn a -> MapSet.member?(bonded_ids, Map.get(a, :id, Map.get(a, :actor_id))) end) |> Enum.shuffle()
      unbonded = Enum.reject(actors, fn a -> MapSet.member?(bonded_ids, Map.get(a, :id, Map.get(a, :actor_id))) end) |> Enum.shuffle()

      (bonded ++ unbonded)
      |> Enum.chunk_every(@max_table_size)
      |> Enum.with_index()
      |> Enum.map(fn {chunk, idx} ->
        sub_key = if idx == 0, do: key, else: "#{key}:#{idx}"
        {sub_key, chunk}
      end)
    end
  end
end
