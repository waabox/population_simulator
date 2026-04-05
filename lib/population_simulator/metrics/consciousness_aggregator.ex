defmodule PopulationSimulator.Metrics.ConsciousnessAggregator do
  @moduledoc """
  SQL queries for consciousness UI data: dissonance, events, bonds,
  perceptions, intentions, café previews, and per-actor consciousness.
  """

  alias PopulationSimulator.Repo

  def dissonance_distribution(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT
          CASE
            WHEN d.dissonance < 0.3 THEN 'low'
            WHEN d.dissonance < 0.5 THEN 'medium'
            ELSE 'high'
          END as level,
          COUNT(*) as cnt
        FROM decisions d
        JOIN actor_populations ap ON ap.actor_id = d.actor_id
        WHERE ap.population_id = ?1
          AND d.dissonance IS NOT NULL
          AND d.measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
        GROUP BY level
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def dissonance_by_stratum(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT json_extract(a.profile, '$.stratum') as stratum,
               ROUND(AVG(d.dissonance), 3) as avg_dissonance,
               COUNT(*) as cnt
        FROM decisions d
        JOIN actors a ON a.id = d.actor_id
        JOIN actor_populations ap ON ap.actor_id = d.actor_id
        WHERE ap.population_id = ?1
          AND d.dissonance IS NOT NULL
          AND d.measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
        GROUP BY stratum
        ORDER BY avg_dissonance DESC
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def active_events_summary(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT e.description,
               json_extract(a.profile, '$.stratum') as stratum,
               e.duration, e.remaining,
               json_extract(e.mood_impact, '$.economic_confidence') as econ_impact,
               json_extract(e.mood_impact, '$.social_anger') as anger_impact
        FROM actor_events e
        JOIN actors a ON a.id = e.actor_id
        JOIN actor_populations ap ON ap.actor_id = e.actor_id
        WHERE ap.population_id = ?1 AND e.active = 1
        ORDER BY e.inserted_at DESC
        LIMIT 20
      """, [population_id])

    events = Enum.map(rows, fn row -> to_map(cols, row) end)
    total = length(events)
    negative = Enum.count(events, fn e -> (e["econ_impact"] || 0) < 0 or (e["anger_impact"] || 0) > 0 end)

    %{events: Enum.take(events, 5), total: total, negative: negative, positive: total - negative}
  end

  def bonds_summary(population_id) do
    %{rows: [[total, avg_affinity, formed_count]]} =
      Repo.query!("""
        SELECT COUNT(*) as total,
               ROUND(AVG(b.affinity), 2) as avg_affinity,
               SUM(CASE WHEN b.formed_at IS NOT NULL THEN 1 ELSE 0 END) as formed
        FROM actor_bonds b
        WHERE b.actor_a_id IN (SELECT actor_id FROM actor_populations WHERE population_id = ?1)
      """, [population_id])

    %{columns: top_cols, rows: top_rows} =
      Repo.query!("""
        SELECT
          json_extract(a1.profile, '$.stratum') || ' (' || a1.age || ')' as actor_a,
          json_extract(a2.profile, '$.stratum') || ' (' || a2.age || ')' as actor_b,
          b.shared_cafes, ROUND(b.affinity, 2) as affinity
        FROM actor_bonds b
        JOIN actors a1 ON a1.id = b.actor_a_id
        JOIN actors a2 ON a2.id = b.actor_b_id
        WHERE b.formed_at IS NOT NULL
          AND b.actor_a_id IN (SELECT actor_id FROM actor_populations WHERE population_id = ?1)
        ORDER BY b.affinity DESC
        LIMIT 5
      """, [population_id])

    %{
      total: total || 0,
      avg_affinity: avg_affinity || 0,
      formed: formed_count || 0,
      top_pairs: Enum.map(top_rows, fn row -> to_map(top_cols, row) end)
    }
  end

  def perceptions_by_zone(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT a.zone,
               p.group_mood,
               COUNT(*) as cnt
        FROM actor_perceptions p
        JOIN actors a ON a.id = p.actor_id
        JOIN actor_populations ap ON ap.actor_id = p.actor_id
        WHERE ap.population_id = ?1
          AND p.measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
        GROUP BY a.zone, p.group_mood
        ORDER BY a.zone
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def active_intentions_summary(population_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT SUBSTR(i.description, 1, 50) as intent,
               json_extract(a.profile, '$.stratum') as stratum,
               i.urgency,
               COUNT(*) as cnt
        FROM actor_intentions i
        JOIN actors a ON a.id = i.actor_id
        JOIN actor_populations ap ON ap.actor_id = i.actor_id
        WHERE ap.population_id = ?1 AND i.status = 'pending'
        GROUP BY SUBSTR(i.description, 1, 30), stratum
        ORDER BY cnt DESC
        LIMIT 15
      """, [population_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  def cafe_preview(population_id) do
    %{rows: [[count]]} =
      Repo.query!("""
        SELECT COUNT(*)
        FROM cafe_sessions cs
        WHERE cs.measure_id = (
          SELECT m.id FROM measures m
          WHERE m.population_id = ?1
          ORDER BY m.inserted_at DESC LIMIT 1
        )
      """, [population_id])

    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT cs.group_key, cs.conversation_summary
        FROM cafe_sessions cs
        WHERE cs.measure_id = (
          SELECT m.id FROM measures m
          WHERE m.population_id = ?1
          ORDER BY m.inserted_at DESC LIMIT 1
        )
        ORDER BY RANDOM()
        LIMIT 3
      """, [population_id])

    %{
      total_mesas: count || 0,
      samples: Enum.map(rows, fn row -> to_map(cols, row) end)
    }
  end

  def actor_consciousness(actor_id) do
    narrative = load_actor_narrative(actor_id)
    intentions = load_actor_intentions(actor_id)
    events = load_actor_events(actor_id)
    bonds = load_actor_bonds(actor_id)
    perception = load_actor_perception(actor_id)
    dissonance = load_actor_dissonance(actor_id)

    %{
      narrative: narrative,
      intentions: intentions,
      events: events,
      bonds: bonds,
      perception: perception,
      dissonance: dissonance
    }
  end

  defp load_actor_narrative(actor_id) do
    case Repo.query!("SELECT narrative, self_observations, version FROM actor_summaries WHERE actor_id = ?1 ORDER BY version DESC LIMIT 1", [actor_id]) do
      %{rows: [[narrative, observations, version]]} ->
        %{narrative: narrative, observations: Jason.decode!(observations || "[]"), version: version}
      _ -> nil
    end
  end

  defp load_actor_intentions(actor_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT description, urgency, status, inserted_at
        FROM actor_intentions
        WHERE actor_id = ?1
        ORDER BY inserted_at DESC
        LIMIT 5
      """, [actor_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  defp load_actor_events(actor_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT description, duration, remaining, active, inserted_at
        FROM actor_events
        WHERE actor_id = ?1
        ORDER BY inserted_at DESC
        LIMIT 5
      """, [actor_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  defp load_actor_bonds(actor_id) do
    %{columns: cols, rows: rows} =
      Repo.query!("""
        SELECT
          CASE WHEN b.actor_a_id = ?1 THEN b.actor_b_id ELSE b.actor_a_id END as partner_id,
          CASE WHEN b.actor_a_id = ?1
            THEN json_extract(a2.profile, '$.stratum') || ' (' || a2.age || ', ' || a2.zone || ')'
            ELSE json_extract(a1.profile, '$.stratum') || ' (' || a1.age || ', ' || a1.zone || ')'
          END as partner_desc,
          b.shared_cafes, ROUND(b.affinity, 2) as affinity
        FROM actor_bonds b
        JOIN actors a1 ON a1.id = b.actor_a_id
        JOIN actors a2 ON a2.id = b.actor_b_id
        WHERE (b.actor_a_id = ?1 OR b.actor_b_id = ?1) AND b.formed_at IS NOT NULL
        ORDER BY b.affinity DESC
        LIMIT 10
      """, [actor_id, actor_id, actor_id])

    Enum.map(rows, fn row -> to_map(cols, row) end)
  end

  defp load_actor_perception(actor_id) do
    case Repo.query!("""
      SELECT p.group_mood, p.referent_influence
      FROM actor_perceptions p
      WHERE p.actor_id = ?1
      ORDER BY p.inserted_at DESC
      LIMIT 1
    """, [actor_id]) do
      %{rows: [[group_mood, referent_influence]]} ->
        %{group_mood: Jason.decode!(group_mood || "{}"), referent_influence: referent_influence}
      _ -> nil
    end
  end

  defp load_actor_dissonance(actor_id) do
    case Repo.query!("""
      SELECT dissonance FROM decisions
      WHERE actor_id = ?1 AND dissonance IS NOT NULL
      ORDER BY inserted_at DESC LIMIT 1
    """, [actor_id]) do
      %{rows: [[val]]} -> val
      _ -> nil
    end
  end

  defp to_map(columns, row) do
    columns |> Enum.zip(row) |> Map.new()
  end
end
