defmodule Mix.Tasks.Sim.Dashboard do
  use Mix.Task

  @shortdoc "Shows full population dashboard (no LLM calls)"

  alias PopulationSimulator.Repo

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [population: :string]
      )

    population_name = opts[:population] || raise "Required: --population"

    population = Repo.get_by!(PopulationSimulator.Populations.Population, name: population_name)

    %{rows: [[actor_count]]} =
      Repo.query!("SELECT COUNT(*) FROM actor_populations WHERE population_id = ?1", [population.id])

    %{rows: [[measure_count]]} =
      Repo.query!(
        "SELECT COUNT(DISTINCT d.measure_id) FROM decisions d JOIN actor_populations ap ON ap.actor_id = d.actor_id WHERE ap.population_id = ?1",
        [population.id]
      )

    IO.puts("")
    IO.puts("===========================================================================")
    IO.puts("  DASHBOARD: #{population.name}")
    IO.puts("  #{actor_count} actors | #{measure_count} measures processed")
    IO.puts("===========================================================================")

    print_demographics(population.id)
    print_mood(population.id)
    print_mood_evolution(population.id)
    print_approval_by_measure(population.id)
    print_top_beliefs(population.id)
    print_emergent_nodes(population.id)
    print_most_volatile(population.id)
    print_actor_samples(population.id)

    IO.puts("")
  end

  defp print_demographics(population_id) do
    IO.puts("\n--- Demographics ---")

    print_dimension(population_id, "stratum", "Stratum")
    print_dimension(population_id, "zone", "Zone")
    print_dimension(population_id, "employment_type", "Employment")

    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          CASE
            WHEN a.political_orientation <= 3 THEN 'left (1-3)'
            WHEN a.political_orientation <= 5 THEN 'center (4-5)'
            WHEN a.political_orientation <= 7 THEN 'center-right (6-7)'
            ELSE 'right (8-10)'
          END as bloc,
          COUNT(*) as n
        FROM actors a
        JOIN actor_populations ap ON ap.actor_id = a.id
        WHERE ap.population_id = ?1
        GROUP BY 1 ORDER BY 1
        """,
        [population_id]
      )

    IO.puts("  Political orientation:")
    Enum.each(rows, fn [bloc, n] -> IO.puts("    #{String.pad_trailing(bloc, 22)} #{n}") end)
  end

  defp print_dimension(population_id, dimension, label) do
    %{rows: rows} =
      Repo.query!(
        "SELECT a.#{dimension}, COUNT(*) as n FROM actors a JOIN actor_populations ap ON ap.actor_id = a.id WHERE ap.population_id = ?1 GROUP BY 1 ORDER BY 2 DESC",
        [population_id]
      )

    total = Enum.reduce(rows, 0, fn [_, n], acc -> acc + n end)

    IO.puts("  #{label}:")

    Enum.each(rows, fn [value, n] ->
      pct = Float.round(n / max(total, 1) * 100, 1)
      IO.puts("    #{String.pad_trailing(to_string(value), 22)} #{n} (#{pct}%)")
    end)
  end

  defp print_mood(population_id) do
    %{rows: [row]} =
      Repo.query!(
        """
        SELECT
          ROUND(AVG(m.economic_confidence), 1),
          ROUND(AVG(m.government_trust), 1),
          ROUND(AVG(m.personal_wellbeing), 1),
          ROUND(AVG(m.social_anger), 1),
          ROUND(AVG(m.future_outlook), 1)
        FROM actor_moods m
        JOIN (SELECT actor_id, MAX(inserted_at) as max_ts FROM actor_moods GROUP BY actor_id) latest
          ON latest.actor_id = m.actor_id AND latest.max_ts = m.inserted_at
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        WHERE ap.population_id = ?1
        """,
        [population_id]
      )

    [econ, trust, well, anger, future] = row

    IO.puts("\n--- Current Mood (averages) ---")
    IO.puts("  Economic confidence:  #{bar(econ)} #{econ}/10")
    IO.puts("  Government trust:     #{bar(trust)} #{trust}/10")
    IO.puts("  Personal wellbeing:   #{bar(well)} #{well}/10")
    IO.puts("  Social anger:         #{bar(anger)} #{anger}/10")
    IO.puts("  Future outlook:       #{bar(future)} #{future}/10")
  end

  defp print_mood_evolution(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          ms.title,
          ROUND(AVG(m.economic_confidence), 1),
          ROUND(AVG(m.government_trust), 1),
          ROUND(AVG(m.personal_wellbeing), 1),
          ROUND(AVG(m.social_anger), 1),
          ROUND(AVG(m.future_outlook), 1)
        FROM actor_moods m
        JOIN measures ms ON ms.id = m.measure_id
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        WHERE ap.population_id = ?1 AND m.measure_id IS NOT NULL
        GROUP BY m.measure_id, ms.title
        ORDER BY MIN(m.inserted_at)
        """,
        [population_id]
      )

    if rows != [] do
      IO.puts("\n--- Mood Evolution ---")
      IO.puts("  #{String.pad_trailing("Measure", 40)} | Econ | Trust | Well | Anger | Future")
      IO.puts("  #{String.duplicate("-", 78)}")

      Enum.each(rows, fn [title, econ, trust, well, anger, future] ->
        name = String.pad_trailing(String.slice(title || "", 0, 38), 40)
        IO.puts("  #{name} | #{pad(econ)} | #{pad(trust)} | #{pad(well)} | #{pad(anger)} | #{pad(future)}")
      end)
    end
  end

  defp print_approval_by_measure(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          ms.title,
          COUNT(*) as total,
          SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) as approved,
          ROUND(100.0 * SUM(CASE WHEN d.agreement = 1 THEN 1 ELSE 0 END) / MAX(COUNT(*), 1), 1) as pct,
          ROUND(AVG(d.intensity), 1) as avg_intensity
        FROM decisions d
        JOIN measures ms ON ms.id = d.measure_id
        JOIN actor_populations ap ON ap.actor_id = d.actor_id
        WHERE ap.population_id = ?1
        GROUP BY d.measure_id, ms.title
        ORDER BY MIN(d.inserted_at)
        """,
        [population_id]
      )

    if rows != [] do
      IO.puts("\n--- Approval by Measure ---")
      IO.puts("  #{String.pad_trailing("Measure", 40)} | Total | Approved |   %   | Intensity")
      IO.puts("  #{String.duplicate("-", 82)}")

      Enum.each(rows, fn [title, total, approved, pct, intensity] ->
        name = String.pad_trailing(String.slice(title || "", 0, 38), 40)
        IO.puts("  #{name} | #{String.pad_leading("#{total}", 5)} | #{String.pad_leading("#{approved}", 8)} | #{String.pad_leading("#{pct}%", 5)} | #{intensity}")
      end)
    end
  end

  defp print_top_beliefs(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          je.value ->> '$.from',
          je.value ->> '$.to',
          je.value ->> '$.type',
          ROUND(AVG(CAST(je.value ->> '$.weight' AS REAL)), 2),
          COUNT(*)
        FROM actor_beliefs ab
        JOIN (SELECT actor_id, MAX(inserted_at) as max_ts FROM actor_beliefs GROUP BY actor_id) latest
          ON latest.actor_id = ab.actor_id AND latest.max_ts = ab.inserted_at
        JOIN actor_populations ap ON ap.actor_id = ab.actor_id
        , json_each(ab.graph, '$.edges') je
        WHERE ap.population_id = ?1
        GROUP BY 1, 2, 3
        HAVING COUNT(*) >= 10
        ORDER BY ABS(AVG(CAST(je.value ->> '$.weight' AS REAL))) DESC
        LIMIT 10
        """,
        [population_id]
      )

    if rows != [] do
      IO.puts("\n--- Top Beliefs (10+ actors) ---")

      Enum.each(rows, fn [from, to, type, avg_w, count] ->
        type_tag = if type == "causal", do: "C", else: "E"
        IO.puts("  [#{type_tag}] #{String.pad_trailing("#{from} -> #{to}", 40)} #{format_weight(avg_w)} (#{count} actors)")
      end)
    end
  end

  defp print_emergent_nodes(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          node_id,
          COUNT(DISTINCT actor_id) as total_actors
        FROM (
          SELECT ab.actor_id, jn.value ->> '$.id' as node_id
          FROM actor_beliefs ab
          JOIN (SELECT actor_id, MAX(inserted_at) as max_ts FROM actor_beliefs GROUP BY actor_id) latest
            ON latest.actor_id = ab.actor_id AND latest.max_ts = ab.inserted_at
          JOIN actor_populations ap ON ap.actor_id = ab.actor_id
          , json_each(ab.graph, '$.nodes') jn
          WHERE ap.population_id = ?1 AND jn.value ->> '$.type' = 'emergent'
        )
        GROUP BY node_id
        HAVING total_actors >= 5
        ORDER BY total_actors DESC
        LIMIT 10
        """,
        [population_id]
      )

    if rows != [] do
      IO.puts("\n--- Emergent Concepts (top 10, 5+ actors) ---")

      Enum.each(rows, fn [node_id, count] ->
        IO.puts("  #{String.pad_trailing(to_string(node_id), 35)} #{count} actors")
      end)
    end
  end

  defp print_most_volatile(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          a.stratum,
          a.zone,
          a.age,
          a.employment_type,
          a.political_orientation,
          COUNT(d.id) as decisions,
          MAX(m.social_anger) - MIN(m.social_anger) as anger_swing,
          MAX(m.government_trust) - MIN(m.government_trust) as trust_swing
        FROM actors a
        JOIN actor_populations ap ON ap.actor_id = a.id
        JOIN decisions d ON d.actor_id = a.id
        JOIN actor_moods m ON m.actor_id = a.id AND m.decision_id IS NOT NULL
        WHERE ap.population_id = ?1
        GROUP BY a.id
        HAVING COUNT(d.id) >= 2
        ORDER BY (anger_swing + trust_swing) DESC
        LIMIT 5
        """,
        [population_id]
      )

    if rows != [] do
      IO.puts("\n--- Most Volatile Actors (top 5) ---")
      IO.puts("  #{String.pad_trailing("Profile", 45)} | Decisions | Anger swing | Trust swing")
      IO.puts("  #{String.duplicate("-", 82)}")

      Enum.each(rows, fn [stratum, zone, age, employment, orientation, decisions, anger, trust] ->
        profile = "#{age}yo #{stratum} #{zone} #{employment} pol:#{orientation}"
        IO.puts("  #{String.pad_trailing(String.slice(profile, 0, 43), 45)} | #{String.pad_leading("#{decisions}", 9)} | #{String.pad_leading("#{anger}", 11)} | #{String.pad_leading("#{trust}", 11)}")
      end)
    end
  end

  defp print_actor_samples(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          a.age, a.stratum, a.zone, a.employment_type, a.political_orientation,
          m.economic_confidence, m.government_trust, m.personal_wellbeing,
          m.social_anger, m.future_outlook, m.narrative
        FROM actor_moods m
        JOIN (SELECT actor_id, MAX(inserted_at) as max_ts FROM actor_moods GROUP BY actor_id) latest
          ON latest.actor_id = m.actor_id AND latest.max_ts = m.inserted_at
        JOIN actor_populations ap ON ap.actor_id = m.actor_id
        JOIN actors a ON a.id = m.actor_id
        WHERE ap.population_id = ?1 AND m.narrative IS NOT NULL AND m.narrative != ''
        ORDER BY RANDOM()
        LIMIT 5
        """,
        [population_id]
      )

    if rows != [] do
      IO.puts("\n--- Random Actor Voices (5 samples) ---")

      Enum.each(rows, fn [age, stratum, zone, employment, orientation, econ, trust, well, anger, future, narrative] ->
        IO.puts("")
        IO.puts("  [#{age}yo | #{stratum} | #{zone} | #{employment} | pol:#{orientation}]")
        IO.puts("  Mood: econ:#{econ} trust:#{trust} well:#{well} anger:#{anger} future:#{future}")
        IO.puts("  \"#{String.slice(to_string(narrative), 0, 200)}\"")
      end)
    end
  end

  defp bar(nil), do: String.pad_trailing("", 10)

  defp bar(val) when is_number(val) do
    filled = round(val)
    String.duplicate("█", filled) <> String.duplicate("░", 10 - filled)
  end

  defp pad(nil), do: "  -  "
  defp pad(n), do: String.pad_leading("#{n}", 5)

  defp format_weight(nil), do: "  -  "
  defp format_weight(w) when w >= 0, do: "+#{w}"
  defp format_weight(w), do: "#{w}"
end
