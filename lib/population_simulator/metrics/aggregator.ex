defmodule PopulationSimulator.Metrics.Aggregator do
  @moduledoc """
  SQL-based aggregation of simulation results.
  Computes approval rates, intensity distributions, and breakdowns
  by demographic dimensions.
  """

  alias PopulationSimulator.Repo

  def summary(measure_id) do
    {:ok,
     %{
       global: global_approval(measure_id),
       by_stratum: by_dimension(measure_id, "stratum"),
       by_zone: by_dimension(measure_id, "zone"),
       by_employment: by_dimension(measure_id, "employment_type"),
       by_orientation: by_orientation(measure_id),
       histogram: intensity_histogram(measure_id)
     }}
  end

  defp global_approval(measure_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          COUNT(*) as total,
          SUM(CASE WHEN agreement = 1 THEN 1 ELSE 0 END) as approved,
          SUM(CASE WHEN agreement = 0 THEN 1 ELSE 0 END) as rejected,
          ROUND(AVG(intensity), 2) as avg_intensity,
          ROUND(
            100.0 * SUM(CASE WHEN agreement = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1
          ) as approval_pct
        FROM decisions
        WHERE measure_id = ?1
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
          SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) as approved,
          ROUND(AVG(d.intensity), 2) as avg_intensity,
          ROUND(100.0 * SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as approval_pct
        FROM decisions d
        JOIN actors a ON a.id = d.actor_id
        WHERE d.measure_id = ?1
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
          END as bloc,
          COUNT(*) as total,
          ROUND(100.0 * SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as approval_pct,
          ROUND(AVG(d.intensity), 2) as avg_intensity
        FROM decisions d
        JOIN actors a ON a.id = d.actor_id
        WHERE d.measure_id = ?1
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
        WHERE measure_id = ?1
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
    |> Map.new(fn {col, val} -> {col, val} end)
  end
end
