defmodule PopulationSimulator.Metrics.Aggregator do
  @moduledoc """
  SQL-based aggregation of simulation results.
  Computes approval rates, intensity distributions, and breakdowns
  by demographic dimensions.
  """

  alias PopulationSimulator.Repo

  def summary(measure_id) do
    {:ok, uuid_bin} = Ecto.UUID.dump(measure_id)

    {:ok,
     %{
       global: global_approval(uuid_bin),
       by_stratum: by_dimension(uuid_bin, "stratum"),
       by_zone: by_dimension(uuid_bin, "zone"),
       by_employment: by_dimension(uuid_bin, "employment_type"),
       by_orientation: by_orientation(uuid_bin),
       histogram: intensity_histogram(uuid_bin)
     }}
  end

  defp global_approval(measure_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE agreement = true) as approved,
          COUNT(*) FILTER (WHERE agreement = false) as rejected,
          ROUND(AVG(intensity)::numeric, 2) as avg_intensity,
          ROUND(
            100.0 * COUNT(*) FILTER (WHERE agreement = true) / NULLIF(COUNT(*), 0), 1
          ) as approval_pct
        FROM decisions
        WHERE measure_id = $1
        """,
        [measure_id]
      )

    to_map(columns, List.first(rows))
  end

  defp by_dimension(measure_id, dimension) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          a.#{dimension} as dimension,
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE d.agreement = true) as approved,
          ROUND(AVG(d.intensity)::numeric, 2) as avg_intensity,
          ROUND(100.0 * COUNT(*) FILTER (WHERE d.agreement = true) / NULLIF(COUNT(*), 0), 1) as approval_pct
        FROM decisions d
        JOIN actors a ON a.id = d.actor_id
        WHERE d.measure_id = $1
        GROUP BY 1
        ORDER BY approval_pct DESC
        """,
        [measure_id]
      )

    Enum.map(rows, &to_map(columns, &1))
  end

  defp by_orientation(measure_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          CASE
            WHEN a.political_orientation <= 3 THEN 'left'
            WHEN a.political_orientation <= 5 THEN 'center'
            WHEN a.political_orientation <= 7 THEN 'center_right'
            ELSE 'right'
          END as bloque,
          COUNT(*) as total,
          ROUND(100.0 * COUNT(*) FILTER (WHERE d.agreement = true) / NULLIF(COUNT(*), 0), 1) as approval_pct,
          ROUND(AVG(d.intensity)::numeric, 2) as avg_intensity
        FROM decisions d
        JOIN actors a ON a.id = d.actor_id
        WHERE d.measure_id = $1
        GROUP BY 1
        ORDER BY 1
        """,
        [measure_id]
      )

    Enum.map(rows, &to_map(columns, &1))
  end

  defp intensity_histogram(measure_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT intensity, COUNT(*) as n
        FROM decisions
        WHERE measure_id = $1
        GROUP BY 1
        ORDER BY 1
        """,
        [measure_id]
      )

    Enum.map(rows, &to_map(columns, &1))
  end

  defp to_map(_columns, nil), do: %{}

  defp to_map(columns, row) do
    columns
    |> Enum.zip(row)
    |> Map.new(fn {col, val} -> {col, normalize_value(val)} end)
  end

  defp normalize_value(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_value(val), do: val
end
