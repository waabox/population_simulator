defmodule PopulationSimulator.DataPipeline.PopulationSampler do
  @moduledoc """
  Weighted sampling using PONDERA from EPH.
  Ensures the sample distribution reflects the actual GBA population structure.
  """

  def sample(n, individuos) do
    {dist, total} = build_cumulative(individuos)

    Enum.map(1..n, fn _ ->
      target = :rand.uniform() * total
      binary_search(dist, target, 0, tuple_size(dist) - 1)
    end)
  end

  defp build_cumulative(individuos) do
    {dist, total} =
      Enum.map_reduce(individuos, 0, fn ind, acc ->
        nuevo = acc + ind.pondera
        {{nuevo, ind}, nuevo}
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
