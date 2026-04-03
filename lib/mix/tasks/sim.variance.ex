defmodule Mix.Tasks.Sim.Variance do
  @moduledoc """
  Analyzes simulation results for signs of LLM-generated patterns:
  - Artificial consensus (all actors converging to same opinion)
  - Emergent node bias (same concepts appearing across >50% of actors)
  - Belief graph homogenization (edge weight std decreasing over time)
  - Mood dimension clustering (actors bunching in narrow ranges)

  Usage:
    mix sim.variance --population "Panel A"
  """

  use Mix.Task

  alias PopulationSimulator.Repo
  import Ecto.Query

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      strict: [population: :string],
      aliases: [p: :population]
    )

    population_name = opts[:population] || raise "Missing --population"

    pop = Repo.one!(from p in "populations", where: p.name == ^population_name, select: %{id: p.id})
    population_id = pop.id

    IO.puts("=== VARIANCE ANALYSIS: #{population_name} ===\n")

    check_consensus(population_id)
    check_emergent_bias(population_id)
    check_mood_clustering(population_id)
    check_belief_homogenization(population_id)
  end

  defp check_consensus(population_id) do
    IO.puts("--- Consensus Detection ---")

    %{rows: rows} = Repo.query!(
      """
      SELECT
        ms.title,
        COUNT(*) as total,
        ROUND(100.0 * SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as approval_pct,
        ROUND(AVG(d.intensity), 1) as avg_intensity,
        ROUND(AVG(d.intensity * d.intensity) - AVG(d.intensity) * AVG(d.intensity), 2) as intensity_variance
      FROM decisions d
      JOIN actors a ON a.id = d.actor_id
      JOIN actor_populations ap ON ap.actor_id = a.id
      JOIN measures ms ON ms.id = d.measure_id
      WHERE ap.population_id = ?1
      GROUP BY d.measure_id, ms.title
      ORDER BY d.inserted_at
      """,
      [population_id]
    )

    Enum.each(rows, fn [title, total, approval, avg_int, int_var] ->
      warnings = []
      warnings = if approval > 90.0 or approval < 10.0, do: ["EXTREME CONSENSUS" | warnings], else: warnings
      warnings = if int_var != nil and int_var < 1.5, do: ["LOW VARIANCE" | warnings], else: warnings

      flag = if warnings != [], do: " WARNING: #{Enum.join(warnings, ", ")}", else: ""
      IO.puts("  #{title}: #{approval}% approval, avg_intensity=#{avg_int}, var=#{int_var || "?"} (n=#{total})#{flag}")
    end)

    IO.puts("")
  end

  defp check_emergent_bias(population_id) do
    IO.puts("--- Emergent Node Bias ---")

    total_actors = Repo.one!(
      from ap in "actor_populations",
        where: ap.population_id == ^population_id,
        select: count(ap.actor_id)
    )

    %{rows: rows} = Repo.query!(
      """
      SELECT
        jn.value ->> '$.id' as node_id,
        jn.value ->> '$.added_at' as added_at,
        COUNT(DISTINCT ab.actor_id) as actor_count
      FROM actor_beliefs ab
      JOIN (
        SELECT actor_id, MAX(inserted_at) as max_ts
        FROM actor_beliefs
        GROUP BY actor_id
      ) latest ON latest.actor_id = ab.actor_id AND latest.max_ts = ab.inserted_at
      JOIN actor_populations ap ON ap.actor_id = ab.actor_id
      , json_each(ab.graph, '$.nodes') jn
      WHERE ap.population_id = ?1
        AND jn.value ->> '$.type' = 'emergent'
      GROUP BY node_id, added_at
      ORDER BY actor_count DESC
      """,
      [population_id]
    )

    if rows == [] do
      IO.puts("  No emergent nodes found.")
    else
      Enum.each(rows, fn [node_id, added_at, count] ->
        pct = Float.round(100.0 * count / max(total_actors, 1), 1)
        flag = if pct > 50.0, do: " WARNING: MODEL BIAS (>50% actors share this concept)", else: ""
        IO.puts("  #{node_id} (from: #{added_at}): #{count}/#{total_actors} actors (#{pct}%)#{flag}")
      end)
    end

    IO.puts("")
  end

  defp check_mood_clustering(population_id) do
    IO.puts("--- Mood Clustering ---")

    %{rows: rows} = Repo.query!(
      """
      SELECT
        ms.title,
        ROUND(AVG(m.economic_confidence), 1) as ec_mean,
        ROUND(AVG(m.economic_confidence * m.economic_confidence) - AVG(m.economic_confidence) * AVG(m.economic_confidence), 2) as ec_var,
        ROUND(AVG(m.government_trust), 1) as gt_mean,
        ROUND(AVG(m.government_trust * m.government_trust) - AVG(m.government_trust) * AVG(m.government_trust), 2) as gt_var,
        ROUND(AVG(m.social_anger), 1) as sa_mean,
        ROUND(AVG(m.social_anger * m.social_anger) - AVG(m.social_anger) * AVG(m.social_anger), 2) as sa_var
      FROM actor_moods m
      JOIN measures ms ON ms.id = m.measure_id
      JOIN actor_populations ap ON ap.actor_id = m.actor_id
      WHERE ap.population_id = ?1 AND m.measure_id IS NOT NULL
      GROUP BY m.measure_id, ms.title
      ORDER BY m.inserted_at
      """,
      [population_id]
    )

    Enum.each(rows, fn [title, ec_m, ec_v, gt_m, gt_v, sa_m, sa_v] ->
      dims = [{"economic_confidence", ec_m, ec_v}, {"government_trust", gt_m, gt_v}, {"social_anger", sa_m, sa_v}]
      low_var = Enum.filter(dims, fn {_, _, v} -> v != nil and v < 1.0 end)

      flag = if length(low_var) >= 2, do: " WARNING: MOOD CLUSTERING", else: ""
      IO.puts("  #{title}:#{flag}")

      Enum.each(dims, fn {name, mean, var} ->
        dim_flag = if var != nil and var < 1.0, do: " !", else: ""
        IO.puts("    #{name}: mean=#{mean} var=#{var || "?"}#{dim_flag}")
      end)
    end)

    IO.puts("")
  end

  defp check_belief_homogenization(population_id) do
    IO.puts("--- Belief Homogenization ---")

    %{rows: rows} = Repo.query!(
      """
      SELECT
        ms.title,
        je.value ->> '$.from' as edge_from,
        je.value ->> '$.to' as edge_to,
        ROUND(AVG(CAST(je.value ->> '$.weight' AS REAL)), 2) as avg_weight,
        ROUND(AVG(CAST(je.value ->> '$.weight' AS REAL) * CAST(je.value ->> '$.weight' AS REAL))
              - AVG(CAST(je.value ->> '$.weight' AS REAL)) * AVG(CAST(je.value ->> '$.weight' AS REAL)), 3) as weight_var,
        COUNT(DISTINCT ab.actor_id) as n
      FROM actor_beliefs ab
      JOIN measures ms ON ms.id = ab.measure_id
      JOIN actor_populations ap ON ap.actor_id = ab.actor_id
      , json_each(ab.graph, '$.edges') je
      WHERE ap.population_id = ?1 AND ab.measure_id IS NOT NULL
      GROUP BY ms.title, edge_from, edge_to
      HAVING n >= 10
      ORDER BY ab.inserted_at, weight_var ASC
      LIMIT 20
      """,
      [population_id]
    )

    if rows == [] do
      IO.puts("  Not enough data for homogenization analysis.")
    else
      Enum.each(rows, fn [title, from, to, avg_w, var, n] ->
        flag = if var != nil and var < 0.01, do: " WARNING: HOMOGENIZED", else: ""
        IO.puts("  #{title} | #{from}->#{to}: avg=#{avg_w} var=#{var || "?"} (n=#{n})#{flag}")
      end)
    end

    IO.puts("")
  end
end
