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

  def mood_summary(population_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          ROUND(AVG(m.economic_confidence), 1) as economic_confidence,
          ROUND(AVG(m.government_trust), 1) as government_trust,
          ROUND(AVG(m.personal_wellbeing), 1) as personal_wellbeing,
          ROUND(AVG(m.social_anger), 1) as social_anger,
          ROUND(AVG(m.future_outlook), 1) as future_outlook,
          COUNT(*) as actor_count
        FROM actor_moods m
        JOIN (
          SELECT actor_id, MAX(inserted_at) as max_ts
          FROM actor_moods
          GROUP BY actor_id
        ) latest ON latest.actor_id = m.actor_id AND latest.max_ts = m.inserted_at
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        WHERE ap.population_id = ?1
        """,
        [population_id]
      )

    to_map(columns, List.first(rows))
  end

  def mood_evolution(population_id) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        SELECT
          ms.title as measure,
          ROUND(AVG(m.economic_confidence), 1) as economic_confidence,
          ROUND(AVG(m.government_trust), 1) as government_trust,
          ROUND(AVG(m.personal_wellbeing), 1) as personal_wellbeing,
          ROUND(AVG(m.social_anger), 1) as social_anger,
          ROUND(AVG(m.future_outlook), 1) as future_outlook
        FROM actor_moods m
        JOIN measures ms ON ms.id = m.measure_id
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        WHERE ap.population_id = ?1 AND m.measure_id IS NOT NULL
        GROUP BY m.measure_id, ms.title
        ORDER BY m.inserted_at
        """,
        [population_id]
      )

    Enum.map(rows, &to_map(columns, &1))
  end

  def opinion_shifts(population_id, measure_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT COUNT(*) FROM (
          SELECT d1.actor_id
          FROM decisions d1
          JOIN decisions d2 ON d2.actor_id = d1.actor_id
          JOIN actor_populations ap ON ap.actor_id = d1.actor_id
          WHERE ap.population_id = ?1
            AND d1.measure_id = ?2
            AND d2.measure_id != ?2
            AND d1.agreement != d2.agreement
            AND d2.inserted_at = (
              SELECT MAX(d3.inserted_at) FROM decisions d3
              WHERE d3.actor_id = d1.actor_id AND d3.measure_id != ?2
              AND d3.inserted_at < d1.inserted_at
            )
          GROUP BY d1.actor_id
        )
        """,
        [population_id, measure_id]
      )

    count
  end

  defp to_map(_columns, nil), do: %{}

  defp to_map(columns, row) do
    columns
    |> Enum.zip(row)
    |> Map.new(fn {col, val} -> {col, val} end)
  end
end
