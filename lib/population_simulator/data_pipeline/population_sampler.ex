defmodule PopulationSimulator.DataPipeline.PopulationSampler do
  @moduledoc """
  Weighted sampling using PONDERA from EPH.
  Ensures the sample distribution reflects the actual GBA population structure.
  """

  def sample(n, individuals) do
    {dist, total} = build_cumulative(individuals)

    Enum.map(1..n, fn _ ->
      target = :rand.uniform() * total
      binary_search(dist, target, 0, tuple_size(dist) - 1)
    end)
  end

  defp build_cumulative(individuals) do
    {dist, total} =
      Enum.map_reduce(individuals, 0, fn ind, acc ->
        new_acc = acc + ind.weight
        {{new_acc, ind}, new_acc}
      end)

    {List.to_tuple(dist), total}
  end

  defp binary_search(dist, _target, lo, hi) when lo >= hi do
    {_, ind} = elem(dist, lo)
    ind
  end

  defp binary_search(dist, target, lo, hi) do
    mid = div(lo + hi, 2)
    {cum, _} = elem(dist, mid)

    if cum < target do
      binary_search(dist, target, mid + 1, hi)
    else
      binary_search(dist, target, lo, mid)
    end
  end
end
