defmodule PopulationSimulator.Metrics.Aggregator do
  @moduledoc """
  SQL-based aggregation of simulation results.
  Computes approval rates, intensity distributions, and breakdowns
  by demographic dimensions.
  """

  alias PopulationSimulator.Repo

  def resumen(measure_id) do
    {:ok, uuid_bin} = Ecto.UUID.dump(measure_id)

    {:ok,
     %{
       global: aprobacion_global(uuid_bin),
       por_estrato: por_dimension(uuid_bin, "estrato"),
       por_zona: por_dimension(uuid_bin, "zona"),
       por_empleo: por_dimension(uuid_bin, "tipo_empleo"),
       por_orientacion: por_orientacion(uuid_bin),
       histograma: histograma_intensidad(uuid_bin)
     }}
  end

  defp aprobacion_global(measure_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE acuerdo = true) as aprueba,
          COUNT(*) FILTER (WHERE acuerdo = false) as rechaza,
          ROUND(AVG(intensidad)::numeric, 2) as intensidad_promedio,
          ROUND(
            100.0 * COUNT(*) FILTER (WHERE acuerdo = true) / NULLIF(COUNT(*), 0), 1
          ) as pct_aprobacion
        FROM decisions
        WHERE measure_id = $1
        """,
        [measure_id]
      )

    to_map(columns, List.first(rows))
  end

  defp por_dimension(measure_id, dimension) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          a.#{dimension} as dimension,
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE d.acuerdo = true) as aprueba,
          ROUND(AVG(d.intensidad)::numeric, 2) as intensidad_promedio,
          ROUND(100.0 * COUNT(*) FILTER (WHERE d.acuerdo = true) / NULLIF(COUNT(*), 0), 1) as pct_aprobacion
        FROM decisions d
        JOIN actors a ON a.id = d.actor_id
        WHERE d.measure_id = $1
        GROUP BY 1
        ORDER BY pct_aprobacion DESC
        """,
        [measure_id]
      )

    Enum.map(rows, &to_map(columns, &1))
  end

  defp por_orientacion(measure_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          CASE
            WHEN a.orientacion_politica <= 3 THEN 'izquierda'
            WHEN a.orientacion_politica <= 5 THEN 'centro'
            WHEN a.orientacion_politica <= 7 THEN 'centro_derecha'
            ELSE 'derecha'
          END as bloque,
          COUNT(*) as total,
          ROUND(100.0 * COUNT(*) FILTER (WHERE d.acuerdo = true) / NULLIF(COUNT(*), 0), 1) as pct_aprobacion,
          ROUND(AVG(d.intensidad)::numeric, 2) as intensidad_promedio
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

  defp histograma_intensidad(measure_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT intensidad, COUNT(*) as n
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
