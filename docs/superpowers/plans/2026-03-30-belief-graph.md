# Belief Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a directed belief graph per actor with causal and emotional edges that evolves with each economic measure, giving actors an internal mental model.

**Architecture:** New `actor_beliefs` table stores full graph snapshots (JSON). A `BeliefGraph` module handles construction, delta application, and humanization. Archetype templates (8 JSON files) seed initial graphs. PromptBuilder, ClaudeClient, and MeasureRunner are extended to include beliefs in the simulation loop.

**Tech Stack:** Elixir/Ecto/SQLite3, JSON graph storage, LLM for template generation and delta updates.

---

### Task 1: Migration — Create actor_beliefs table

**Files:**
- Create: `priv/repo/migrations/20260330200000_create_actor_beliefs.exs`

- [ ] **Step 1: Create the migration**

```elixir
defmodule PopulationSimulator.Repo.Migrations.CreateActorBeliefs do
  use Ecto.Migration

  def change do
    create table(:actor_beliefs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :uuid, on_delete: :delete_all), null: false
      add :decision_id, references(:decisions, type: :uuid, on_delete: :nilify_all)
      add :measure_id, references(:measures, type: :uuid, on_delete: :nilify_all)
      add :graph, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:actor_beliefs, [:actor_id, :inserted_at])
    create index(:actor_beliefs, [:decision_id])
  end
end
```

- [ ] **Step 2: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully, table created.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations/20260330200000_create_actor_beliefs.exs
git commit -m "Add actor_beliefs migration"
```

---

### Task 2: BeliefGraph module — Graph construction and delta application

**Files:**
- Create: `lib/population_simulator/simulation/belief_graph.ex`

- [ ] **Step 1: Create the BeliefGraph module**

```elixir
defmodule PopulationSimulator.Simulation.BeliefGraph do
  @moduledoc """
  Functions for constructing, applying deltas, and humanizing belief graphs.
  A belief graph is a map with "nodes" and "edges" lists stored as JSON.
  """

  @core_nodes ~w(inflation employment taxes dollar state_role social_welfare pensions wages security education healthcare corruption foreign_trade utility_rates private_property)

  def core_nodes, do: @core_nodes

  @doc """
  Applies a belief_update delta to an existing graph, producing a new full graph.

  Delta structure:
    %{
      "modified_edges" => [...],
      "new_edges" => [...],
      "new_nodes" => [...],
      "removed_edges" => [...]
    }
  """
  def apply_delta(graph, nil), do: graph
  def apply_delta(graph, delta) when is_map(delta) do
    graph
    |> add_nodes(delta["new_nodes"] || [])
    |> remove_edges(delta["removed_edges"] || [])
    |> modify_edges(delta["modified_edges"] || [])
    |> add_edges(delta["new_edges"] || [])
    |> clamp_weights()
  end

  @doc """
  Renders the graph as a Spanish-language section for the LLM prompt.
  Edges sorted by absolute weight (most important first).
  """
  def humanize(graph) when is_map(graph) do
    edges = graph["edges"] || []

    causal = edges
      |> Enum.filter(&(&1["type"] == "causal"))
      |> Enum.sort_by(&abs(&1["weight"]), :desc)

    emotional = edges
      |> Enum.filter(&(&1["type"] == "emotional"))
      |> Enum.sort_by(&abs(&1["weight"]), :desc)

    causal_text = if causal == [] do
      "Ninguna."
    else
      causal
      |> Enum.map(fn e ->
        direction = if e["weight"] < 0, do: "menos", else: "mas"
        "- Mas #{humanize_node(e["from"])} → #{direction} #{humanize_node(e["to"])} (peso: #{e["weight"]})"
      end)
      |> Enum.join("\n")
    end

    emotional_text = if emotional == [] do
      "Ninguna."
    else
      emotional
      |> Enum.map(fn e ->
        "- #{humanize_node(e["from"])} → #{e["description"] || humanize_node(e["to"])} (peso: #{e["weight"]})"
      end)
      |> Enum.join("\n")
    end

    """
    === TU MODELO MENTAL (como crees que funciona el mundo) ===

    Relaciones causales:
    #{causal_text}

    Reacciones emocionales:
    #{emotional_text}
    """
  end

  def humanize(nil), do: ""

  @doc """
  Builds an initial graph from an archetype template, applying deterministic
  variations based on the actor's profile.
  """
  def from_template(template, profile) when is_map(template) and is_map(profile) do
    template
    |> apply_profile_variations(profile)
    |> remove_irrelevant_edges(profile)
    |> clamp_weights()
  end

  # --- Private functions ---

  defp add_nodes(graph, []), do: graph
  defp add_nodes(graph, new_nodes) do
    existing_ids = Enum.map(graph["nodes"] || [], & &1["id"]) |> MapSet.new()
    unique_new = Enum.reject(new_nodes, fn n -> MapSet.member?(existing_ids, n["id"]) end)
    Map.update(graph, "nodes", unique_new, &(&1 ++ unique_new))
  end

  defp remove_edges(graph, []), do: graph
  defp remove_edges(graph, to_remove) do
    remove_set = MapSet.new(to_remove, fn e -> {e["from"], e["to"], e["type"]} end)

    Map.update(graph, "edges", [], fn edges ->
      Enum.reject(edges, fn e ->
        MapSet.member?(remove_set, {e["from"], e["to"], e["type"]})
      end)
    end)
  end

  defp modify_edges(graph, []), do: graph
  defp modify_edges(graph, modifications) do
    mod_map = Map.new(modifications, fn e -> {{e["from"], e["to"], e["type"]}, e} end)

    Map.update(graph, "edges", [], fn edges ->
      Enum.map(edges, fn e ->
        key = {e["from"], e["to"], e["type"]}
        case Map.get(mod_map, key) do
          nil -> e
          mod -> Map.merge(e, mod)
        end
      end)
    end)
  end

  defp add_edges(graph, []), do: graph
  defp add_edges(graph, new_edges) do
    existing_set = MapSet.new(graph["edges"] || [], fn e -> {e["from"], e["to"], e["type"]} end)
    unique_new = Enum.reject(new_edges, fn e ->
      MapSet.member?(existing_set, {e["from"], e["to"], e["type"]})
    end)
    Map.update(graph, "edges", unique_new, &(&1 ++ unique_new))
  end

  defp clamp_weights(graph) do
    Map.update(graph, "edges", [], fn edges ->
      Enum.map(edges, fn e ->
        Map.update(e, "weight", 0, fn w ->
          w |> max(-1.0) |> min(1.0)
        end)
      end)
    end)
  end

  defp apply_profile_variations(graph, profile) do
    Map.update(graph, "edges", [], fn edges ->
      Enum.map(edges, fn edge ->
        adjustment = calculate_adjustment(edge, profile)
        Map.update(edge, "weight", 0, &(&1 + adjustment))
      end)
    end)
  end

  defp calculate_adjustment(edge, profile) do
    adj = 0.0

    adj = adj + case profile["employment_type"] do
      "unemployed" ->
        if edge["to"] == "employment" or edge["from"] == "employment", do: 0.1, else: 0.0
      "formal_employee" ->
        if edge["from"] == "taxes", do: -0.05, else: 0.0
      "self_employed" ->
        if edge["from"] == "state_role" and edge["type"] == "causal", do: -0.1, else: 0.0
      _ -> 0.0
    end

    adj = adj + cond do
      (profile["age"] || 30) > 55 ->
        if edge["from"] == "pensions" or edge["to"] == "pensions", do: 0.1, else: 0.0
      (profile["age"] || 30) < 30 ->
        if edge["from"] == "employment", do: 0.05, else: 0.0
      true -> 0.0
    end

    adj = adj + if profile["has_dollars"] == "true" do
      if edge["from"] == "dollar" or edge["to"] == "dollar", do: 0.1, else: 0.0
    else
      0.0
    end

    adj = adj + if profile["receives_welfare"] == "true" do
      if edge["from"] == "social_welfare" and edge["type"] == "emotional", do: 0.15, else: 0.0
    else
      0.0
    end

    adj
  end

  defp remove_irrelevant_edges(graph, profile) do
    Map.update(graph, "edges", [], fn edges ->
      Enum.reject(edges, fn edge ->
        irrelevant?(edge, profile)
      end)
    end)
  end

  defp irrelevant?(edge, profile) do
    cond do
      edge["from"] == "foreign_trade" and profile["employment_type"] in ["unemployed", "inactive"] ->
        :rand.uniform() < 0.7
      edge["from"] == "private_property" and profile["tenure"] in ["lent", "renter"] and profile["stratum"] in ["destitute", "low"] ->
        :rand.uniform() < 0.5
      true ->
        false
    end
  end

  defp humanize_node("inflation"), do: "inflacion"
  defp humanize_node("employment"), do: "empleo"
  defp humanize_node("taxes"), do: "impuestos"
  defp humanize_node("dollar"), do: "dolar"
  defp humanize_node("state_role"), do: "rol del estado"
  defp humanize_node("social_welfare"), do: "planes sociales"
  defp humanize_node("pensions"), do: "jubilaciones"
  defp humanize_node("wages"), do: "salarios"
  defp humanize_node("security"), do: "seguridad"
  defp humanize_node("education"), do: "educacion"
  defp humanize_node("healthcare"), do: "salud"
  defp humanize_node("corruption"), do: "corrupcion"
  defp humanize_node("foreign_trade"), do: "comercio exterior"
  defp humanize_node("utility_rates"), do: "tarifas"
  defp humanize_node("private_property"), do: "propiedad privada"
  defp humanize_node(other), do: String.replace(other, "_", " ")
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/belief_graph.ex
git commit -m "Add BeliefGraph module with delta application and humanization"
```

---

### Task 3: ActorBelief Ecto schema

**Files:**
- Create: `lib/population_simulator/simulation/actor_belief.ex`

- [ ] **Step 1: Create the schema**

```elixir
defmodule PopulationSimulator.Simulation.ActorBelief do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actor_beliefs" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :decision, PopulationSimulator.Simulation.Decision, type: :binary_id
    belongs_to :measure, PopulationSimulator.Simulation.Measure, type: :binary_id
    field :graph, :map
    timestamps(type: :utc_datetime)
  end

  def changeset(belief, attrs) do
    belief
    |> cast(attrs, [:actor_id, :decision_id, :measure_id, :graph])
    |> validate_required([:actor_id, :graph])
  end

  def initial(actor_id, graph) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: nil,
      measure_id: nil,
      graph: graph,
      inserted_at: now,
      updated_at: now
    }
  end

  def from_update(actor_id, decision_id, measure_id, graph) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: decision_id,
      measure_id: measure_id,
      graph: graph,
      inserted_at: now,
      updated_at: now
    }
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/actor_belief.ex
git commit -m "Add ActorBelief Ecto schema"
```

---

### Task 4: Archetype template generation task — sim.beliefs.init

**Files:**
- Create: `lib/mix/tasks/sim.beliefs.init.ex`
- Create: `priv/data/belief_templates/` (directory)

- [ ] **Step 1: Create the Mix task**

```elixir
defmodule Mix.Tasks.Sim.Beliefs.Init do
  use Mix.Task

  @shortdoc "Generates belief graph templates for each archetype via LLM"

  alias PopulationSimulator.LLM.ClaudeClient
  alias PopulationSimulator.Simulation.BeliefGraph

  @archetypes [
    {"destitute_left", "Indigente o de clase baja, orientacion politica de izquierda/kirchnerista (1-5). Vive en el conurbano, probablemente desempleado o informal, recibe planes sociales."},
    {"destitute_right", "Indigente o de clase baja, orientacion politica de derecha/libertaria (6-10). Vive en el conurbano, trabaja informalmente, desconfia del estado."},
    {"lower_middle_left", "Clase media-baja, orientacion de izquierda/peronista (1-5). Empleado formal o cuentapropista, lucha para llegar a fin de mes."},
    {"lower_middle_right", "Clase media-baja, orientacion de derecha/liberal (6-10). Empleado formal, siente que los impuestos lo ahogan, quiere progresar."},
    {"middle_left", "Clase media, orientacion de izquierda/centro (1-5). Profesional o empleado estable, valora el rol del estado en educacion y salud."},
    {"middle_right", "Clase media, orientacion de derecha/PRO-libertario (6-10). Profesional, ahorra en dolares, quiere menos impuestos y menos estado."},
    {"upper_left", "Clase media-alta o alta, orientacion de izquierda/progresista (1-5). Profesional exitoso, cree en la redistribucion y el estado presente."},
    {"upper_right", "Clase media-alta o alta, orientacion de derecha/liberal (6-10). Empresario o profesional, ahorra en dolares, quiere libre mercado y seguridad juridica."}
  ]

  @template_dir "priv/data/belief_templates"

  def run(_args) do
    Mix.Task.run("app.start")

    File.mkdir_p!(@template_dir)

    core_nodes = BeliefGraph.core_nodes()
    core_nodes_text = Enum.join(core_nodes, ", ")

    Enum.each(@archetypes, fn {name, description} ->
      IO.puts("Generating template for #{name}...")

      prompt = """
      Sos un experto en sociologia argentina. Necesito que generes un grafo de creencias para el siguiente arquetipo de ciudadano argentino:

      ARQUETIPO: #{description}

      NODOS DISPONIBLES (conceptos): #{core_nodes_text}

      Genera un grafo JSON con exactamente estos nodos y entre 15 y 25 aristas (edges) que representen:
      1. Relaciones CAUSALES que este arquetipo percibe (type: "causal") — como cree que funciona la economia
      2. Reacciones EMOCIONALES ante cada tema (type: "emotional") — que le genera cada tema

      Peso (weight): -1.0 a 1.0. Negativo = relacion inversa/negativa. Positivo = directa/positiva.

      Responde UNICAMENTE con JSON valido. Sin texto antes ni despues. Sin markdown.

      {
        "nodes": [
          {"id": "inflation", "type": "core"},
          ...todos los 15 nodos core...
        ],
        "edges": [
          {"from": "taxes", "to": "employment", "type": "causal", "weight": -0.7, "description": "More taxes reduce employment"},
          {"from": "inflation", "to": "anger", "type": "emotional", "weight": 0.8, "description": "Inflation makes me angry"},
          ...entre 15 y 25 aristas total...
        ]
      }
      """

      case ClaudeClient.complete(prompt, max_tokens: 2048) do
        {:ok, response} ->
          graph = response.raw_response
          path = Path.join(@template_dir, "#{name}.json")
          File.write!(path, Jason.encode!(graph, pretty: true))
          edge_count = length(graph["edges"] || [])
          IO.puts("  #{name}: #{edge_count} edges saved to #{path}")

        {:error, reason} ->
          IO.puts("  ERROR for #{name}: #{inspect(reason)}")
      end
    end)

    IO.puts("\nDone! Templates saved to #{@template_dir}/")
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.beliefs.init.ex
git commit -m "Add sim.beliefs.init task for archetype template generation"
```

---

### Task 5: Update sim.seed — Assign initial belief graphs from templates

**Files:**
- Modify: `lib/mix/tasks/sim.seed.ex`

- [ ] **Step 1: Add belief graph initialization to sim.seed**

Add a new function call after `create_initial_moods(rows)` in the `run/1` function, and add the corresponding private functions. The full updated file:

```elixir
defmodule Mix.Tasks.Sim.Seed do
  use Mix.Task

  @shortdoc "Seeds population from INDEC EPH files"

  @template_dir "priv/data/belief_templates"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [n: :integer, individual: :string, hogar: :string, population: :string]
      )

    n = opts[:n] || 5_000
    individual = opts[:individual] || "priv/data/eph/individual.txt"
    hogar = opts[:hogar] || "priv/data/eph/hogar.txt"
    population_name = opts[:population]

    IO.puts("Loading EPH GBA...")
    individuos = PopulationSimulator.DataPipeline.EphLoader.load(individual, hogar)
    IO.puts("#{length(individuos)} individuals found in EPH sample")

    IO.puts("Sampling #{n} weighted actors...")
    sample = PopulationSimulator.DataPipeline.PopulationSampler.sample(n, individuos)

    IO.puts("Enriching with synthetic variables...")
    actores = Enum.map(sample, &PopulationSimulator.DataPipeline.ActorEnricher.enrich/1)

    IO.puts("Persisting to DB...")
    rows = PopulationSimulator.Actors.Actor.insert_all(actores)

    IO.puts("Creating initial moods...")
    create_initial_moods(rows)

    IO.puts("Creating initial belief graphs...")
    create_initial_beliefs(rows)

    if population_name do
      assign_to_population(rows, population_name)
    end

    IO.puts("Population of #{n} actors created from real EPH GBA data")

    print_distribution("Stratum", actores, :stratum)
    print_distribution("Zone", actores, :zone)
    print_distribution("Employment", actores, :employment_type)
  end

  defp create_initial_moods(rows) do
    alias PopulationSimulator.{Repo, Simulation.ActorMood}

    rows
    |> Enum.map(fn row -> ActorMood.initial_from_profile(row[:id], row[:profile]) end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(ActorMood, chunk, on_conflict: :nothing)
    end)
  end

  defp create_initial_beliefs(rows) do
    alias PopulationSimulator.{Repo, Simulation.ActorBelief, Simulation.BeliefGraph}

    templates = load_templates()

    if templates == %{} do
      IO.puts("  No belief templates found in #{@template_dir}/ — skipping. Run mix sim.beliefs.init first.")
      return_early()
    else
      rows
      |> Enum.map(fn row ->
        archetype = resolve_archetype(row[:profile])
        template = Map.get(templates, archetype, Map.get(templates, "middle_right", default_graph()))
        graph = BeliefGraph.from_template(template, row[:profile])
        ActorBelief.initial(row[:id], graph)
      end)
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(ActorBelief, chunk, on_conflict: :nothing)
      end)
    end
  end

  defp load_templates do
    if File.dir?(@template_dir) do
      @template_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Map.new(fn filename ->
        name = String.replace_suffix(filename, ".json", "")
        content = @template_dir |> Path.join(filename) |> File.read!() |> Jason.decode!()
        {name, content}
      end)
    else
      %{}
    end
  end

  defp resolve_archetype(profile) do
    stratum = profile["stratum"]
    orientation = profile["political_orientation"] || 5

    stratum_group = cond do
      stratum in ["destitute", "low"] -> "destitute"
      stratum == "lower_middle" -> "lower_middle"
      stratum == "middle" -> "middle"
      stratum in ["upper_middle", "upper"] -> "upper"
      true -> "middle"
    end

    orientation_group = if orientation <= 5, do: "left", else: "right"

    "#{stratum_group}_#{orientation_group}"
  end

  defp default_graph do
    %{
      "nodes" => Enum.map(PopulationSimulator.Simulation.BeliefGraph.core_nodes(), fn id ->
        %{"id" => id, "type" => "core"}
      end),
      "edges" => []
    }
  end

  defp return_early, do: :ok

  defp assign_to_population(rows, population_name) do
    alias PopulationSimulator.{Repo, Populations.Population, Populations.ActorPopulation}

    population =
      case Repo.get_by(Population, name: population_name) do
        nil ->
          {:ok, p} = Repo.insert(Population.changeset(%Population{}, %{name: population_name}))
          IO.puts("Population '#{population_name}' created.")
          p

        existing ->
          existing
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows
    |> Enum.map(fn row ->
      %{
        id: Ecto.UUID.generate(),
        actor_id: row[:id],
        population_id: population.id,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(ActorPopulation, chunk,
        on_conflict: :nothing,
        conflict_target: [:actor_id, :population_id]
      )
    end)

    IO.puts("Assigned #{length(rows)} actors to population '#{population_name}'")
  end

  defp print_distribution(label, actores, key) do
    dist =
      actores
      |> Enum.group_by(&Map.get(&1, key))
      |> Enum.map(fn {k, v} -> {k, length(v)} end)
      |> Enum.sort_by(fn {_, count} -> -count end)

    IO.puts("\n--- #{label} ---")

    Enum.each(dist, fn {k, count} ->
      pct = Float.round(count / length(actores) * 100, 1)
      IO.puts("  #{k}: #{count} (#{pct}%)")
    end)
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.seed.ex
git commit -m "Update sim.seed to create initial belief graphs from templates"
```

---

### Task 6: Update PromptBuilder — Add beliefs section and belief_update request

**Files:**
- Modify: `lib/population_simulator/simulation/prompt_builder.ex`

- [ ] **Step 1: Add build/4 function with beliefs context**

Add a new `build/4` function after the existing `build/3`. This function receives mood_context AND belief_graph. Also keep `build/3` unchanged — it still works without beliefs.

Add this function after `build/3` (line 100):

```elixir
  def build(profile, measure, mood_context, belief_graph) when is_map(profile) do
    alias PopulationSimulator.Simulation.BeliefGraph

    """
    #{base(profile)}

    #{mood_section(mood_context)}

    #{BeliefGraph.humanize(belief_graph)}

    ---

    El gobierno nacional anunció la siguiente medida económica:

    "#{measure.description}"

    Respondé ÚNICAMENTE con JSON válido. Sin texto antes ni después. Sin markdown.

    {
      "agreement": true | false (si estás de acuerdo o no),
      "intensity": <número entero del 1 al 10, donde 1=totalmente en contra y 10=totalmente a favor>,
      "reasoning": "<explicación en primera persona desde tu perfil, máximo 2 oraciones>",
      "personal_impact": "<cómo te afecta esta medida específicamente>",
      "behavior_change": "<qué harías diferente, si algo, ante esta medida>",
      "mood_update": {
        "economic_confidence": <1-10>,
        "government_trust": <1-10>,
        "personal_wellbeing": <1-10>,
        "social_anger": <1-10>,
        "future_outlook": <1-10>,
        "narrative": "<cómo te sentís ahora en general, máximo 2 oraciones>"
      },
      "belief_update": {
        "modified_edges": [{"from": "...", "to": "...", "type": "causal|emotional", "weight": <-1.0 a 1.0>, "description": "..."}],
        "new_edges": [{"from": "...", "to": "...", "type": "causal|emotional", "weight": <-1.0 a 1.0>, "description": "..."}],
        "new_nodes": [{"id": "...", "type": "emergent", "added_at": "nombre de la medida"}],
        "removed_edges": [{"from": "...", "to": "...", "type": "causal|emotional"}]
      }
    }

    IMPORTANTE sobre belief_update:
    - Solo incluí edges que esta medida cambió. No repitas todos los edges.
    - Si no cambió ninguna creencia, dejá los arrays vacíos.
    - Podés agregar nodos emergentes si la medida introduce un concepto nuevo.
    """
  end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/prompt_builder.ex
git commit -m "Add build/4 to PromptBuilder with belief graph context"
```

---

### Task 7: Update ClaudeClient — Parse belief_update

**Files:**
- Modify: `lib/population_simulator/llm/claude_client.ex`

- [ ] **Step 1: Add belief_update to parsed decision**

In `lib/population_simulator/llm/claude_client.ex`, update the `parse_response/1` function. Replace the decision map:

```elixir
        decision = %{
          agreement: parsed["agreement"],
          intensity: parsed["intensity"],
          reasoning: parsed["reasoning"],
          personal_impact: parsed["personal_impact"],
          behavior_change: parsed["behavior_change"],
          tokens_used: usage["input_tokens"] + usage["output_tokens"],
          raw_response: parsed,
          mood_update: parsed["mood_update"],
          belief_update: parsed["belief_update"]
        }
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/llm/claude_client.ex
git commit -m "Parse belief_update from LLM response"
```

---

### Task 8: Update MeasureRunner — Load beliefs, persist updated graphs

**Files:**
- Modify: `lib/population_simulator/simulation/measure_runner.ex`

- [ ] **Step 1: Update MeasureRunner with belief support**

Replace the full content of `lib/population_simulator/simulation/measure_runner.ex`:

```elixir
defmodule PopulationSimulator.Simulation.MeasureRunner do
  @moduledoc """
  Orchestrates running an economic measure against actors.
  Supports population filtering, mood loading, belief graphs, and persistence.
  """

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.Decision,
                              Simulation.ActorMood, Simulation.ActorBelief,
                              Simulation.BeliefGraph}
  import Ecto.Query

  def run(measure_id, opts \\ []) do
    concurrency =
      Keyword.get(
        opts,
        :concurrency,
        Application.get_env(:population_simulator, :llm_concurrency, 30)
      )

    limit = Keyword.get(opts, :limit, nil)
    population_id = Keyword.get(opts, :population_id, nil)

    measure = Repo.get!(PopulationSimulator.Simulation.Measure, measure_id)

    actors = load_actors(population_id, limit)
    total = length(actors)

    IO.puts("Simulation started: #{total} actors, concurrency: #{concurrency}")
    start = System.monotonic_time(:second)

    results =
      actors
      |> Task.async_stream(
        fn actor -> evaluate_actor(actor, measure, measure_id) end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0, tokens: 0, errors: []}, fn
        {:ok, {:ok, _, tokens}}, acc ->
          %{acc | ok: acc.ok + 1, tokens: acc.tokens + (tokens || 0)}

        {:ok, {:error, id, reason}}, acc ->
          %{acc | error: acc.error + 1, errors: [{id, reason} | acc.errors]}

        {:exit, _}, acc ->
          %{acc | error: acc.error + 1}
      end)

    elapsed = System.monotonic_time(:second) - start
    IO.puts("Completed in #{elapsed}s — OK: #{results.ok} | Errors: #{results.error} | Tokens: #{results.tokens}")

    {:ok, results}
  end

  defp load_actors(nil, limit) do
    query = from(a in Actor, select: a)
    query = if limit, do: from(q in query, limit: ^limit), else: query
    Repo.all(query)
  end

  defp load_actors(population_id, _limit) do
    Repo.all(
      from a in Actor,
        join: ap in "actor_populations",
        on: ap.actor_id == a.id,
        where: ap.population_id == ^population_id,
        select: a
    )
  end

  defp evaluate_actor(actor, measure, measure_id) do
    current_mood = load_latest_mood(actor.id)
    current_belief = load_latest_belief(actor.id)
    history = load_decision_history(actor.id, 3)

    prompt = build_prompt(actor.profile, measure, current_mood, current_belief, history)

    case ClaudeClient.complete(prompt, max_tokens: 1024) do
      {:ok, decision} ->
        decision_row = Decision.from_llm_response(actor.id, measure_id, decision)

        Repo.insert_all(Decision, [decision_row],
          on_conflict: :nothing,
          conflict_target: [:actor_id, :measure_id]
        )

        if decision.mood_update do
          mood_row = ActorMood.from_llm_response(
            actor.id,
            decision_row.id,
            measure_id,
            decision.mood_update
          )

          Repo.insert_all(ActorMood, [mood_row], on_conflict: :nothing)
        end

        if current_belief do
          updated_graph = BeliefGraph.apply_delta(current_belief, decision.belief_update)

          belief_row = ActorBelief.from_update(
            actor.id,
            decision_row.id,
            measure_id,
            updated_graph
          )

          Repo.insert_all(ActorBelief, [belief_row], on_conflict: :nothing)
        end

        {:ok, actor.id, decision.tokens_used}

      {:error, reason} ->
        {:error, actor.id, reason}
    end
  end

  defp build_prompt(profile, measure, current_mood, current_belief, history) do
    cond do
      current_mood && current_belief ->
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(profile, measure, mood_context, current_belief)

      current_mood ->
        mood_context = %{current_mood: current_mood, history: history}
        PromptBuilder.build(profile, measure, mood_context)

      true ->
        PromptBuilder.build(profile, measure)
    end
  end

  defp load_latest_mood(actor_id) do
    Repo.one(
      from m in "actor_moods",
        where: m.actor_id == ^actor_id,
        order_by: [desc: m.inserted_at],
        limit: 1,
        select: %{
          economic_confidence: m.economic_confidence,
          government_trust: m.government_trust,
          personal_wellbeing: m.personal_wellbeing,
          social_anger: m.social_anger,
          future_outlook: m.future_outlook,
          narrative: m.narrative
        }
    )
  end

  defp load_latest_belief(actor_id) do
    result = Repo.one(
      from b in "actor_beliefs",
        where: b.actor_id == ^actor_id,
        order_by: [desc: b.inserted_at],
        limit: 1,
        select: b.graph
    )

    case result do
      nil -> nil
      graph when is_binary(graph) -> Jason.decode!(graph)
      graph when is_map(graph) -> graph
    end
  end

  defp load_decision_history(actor_id, n) do
    Repo.all(
      from d in "decisions",
        join: m in "measures",
        on: m.id == d.measure_id,
        where: d.actor_id == ^actor_id,
        order_by: [desc: d.inserted_at],
        limit: ^n,
        select: %{
          measure_title: m.title,
          agreement: d.agreement,
          intensity: d.intensity
        }
    )
    |> Enum.reverse()
    |> Enum.map(fn entry ->
      %{entry | agreement: entry.agreement == 1}
    end)
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/simulation/measure_runner.ex
git commit -m "Update MeasureRunner with belief graph loading and persistence"
```

---

### Task 9: Update Aggregator — Belief metrics

**Files:**
- Modify: `lib/population_simulator/metrics/aggregator.ex`

- [ ] **Step 1: Add belief metric functions**

Add these three public functions to `lib/population_simulator/metrics/aggregator.ex` before the private `to_map` functions:

```elixir
  def belief_summary(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          je.value ->> '$.from' as edge_from,
          je.value ->> '$.to' as edge_to,
          je.value ->> '$.type' as edge_type,
          ROUND(AVG(CAST(je.value ->> '$.weight' AS REAL)), 2) as avg_weight,
          ROUND(AVG((CAST(je.value ->> '$.weight' AS REAL)) * (CAST(je.value ->> '$.weight' AS REAL))), 4) as avg_sq_weight,
          COUNT(*) as actor_count
        FROM actor_beliefs ab
        JOIN (
          SELECT actor_id, MAX(inserted_at) as max_ts
          FROM actor_beliefs
          GROUP BY actor_id
        ) latest ON latest.actor_id = ab.actor_id AND latest.max_ts = ab.inserted_at
        JOIN actor_populations ap ON ap.actor_id = ab.actor_id
        , json_each(ab.graph, '$.edges') je
        WHERE ap.population_id = ?1
        GROUP BY edge_from, edge_to, edge_type
        HAVING actor_count >= 5
        ORDER BY ABS(avg_weight) DESC
        """,
        [population_id]
      )

    Enum.map(rows, fn [from, to, type, avg_w, avg_sq_w, count] ->
      variance = avg_sq_w - avg_w * avg_w
      std = if variance > 0, do: Float.round(:math.sqrt(variance), 2), else: 0.0

      %{
        "from" => from,
        "to" => to,
        "type" => type,
        "avg_weight" => avg_w,
        "std" => std,
        "actor_count" => count
      }
    end)
  end

  def belief_evolution(population_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          ms.title as measure,
          je.value ->> '$.from' as edge_from,
          je.value ->> '$.to' as edge_to,
          je.value ->> '$.type' as edge_type,
          ROUND(AVG(CAST(je.value ->> '$.weight' AS REAL)), 2) as avg_weight
        FROM actor_beliefs ab
        JOIN measures ms ON ms.id = ab.measure_id
        JOIN actor_populations ap ON ap.actor_id = ab.actor_id
        , json_each(ab.graph, '$.edges') je
        WHERE ap.population_id = ?1 AND ab.measure_id IS NOT NULL
        GROUP BY ms.title, edge_from, edge_to, edge_type
        ORDER BY ab.inserted_at, ABS(avg_weight) DESC
        """,
        [population_id]
      )

    Enum.map(rows, fn [measure, from, to, type, avg_w] ->
      %{
        "measure" => measure,
        "from" => from,
        "to" => to,
        "type" => type,
        "avg_weight" => avg_w
      }
    end)
  end

  def emergent_nodes(population_id) do
    %{rows: rows} =
      Repo.query!(
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

    Enum.map(rows, fn [node_id, added_at, count] ->
      %{"node_id" => node_id, "added_at" => added_at, "actor_count" => count}
    end)
  end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/population_simulator/metrics/aggregator.ex
git commit -m "Add belief metrics to Aggregator using json_each"
```

---

### Task 10: Mix Task — sim.beliefs (query beliefs)

**Files:**
- Create: `lib/mix/tasks/sim.beliefs.ex`

- [ ] **Step 1: Create the task**

```elixir
defmodule Mix.Tasks.Sim.Beliefs do
  use Mix.Task

  @shortdoc "Shows belief graph summary for a population"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [population: :string, edge: :string, history: :boolean, emergent: :boolean]
      )

    population_name = opts[:population] || raise "Required: --population"

    alias PopulationSimulator.{Repo, Populations.Population, Metrics.Aggregator}

    population = Repo.get_by!(Population, name: population_name)

    cond do
      opts[:emergent] ->
        show_emergent(population)

      opts[:edge] && opts[:history] ->
        show_edge_history(population, opts[:edge])

      true ->
        show_summary(population)
    end
  end

  defp show_summary(population) do
    alias PopulationSimulator.Metrics.Aggregator

    beliefs = Aggregator.belief_summary(population.id)

    causal = Enum.filter(beliefs, &(&1["type"] == "causal"))
    emotional = Enum.filter(beliefs, &(&1["type"] == "emotional"))

    IO.puts("\n=== Beliefs: #{population.name} ===\n")

    IO.puts("Top causal beliefs (avg weight):")
    causal
    |> Enum.take(10)
    |> Enum.each(fn b ->
      divergence = if b["std"] > 0.25, do: "  ** high divergence", else: ""
      IO.puts("  #{pad_edge(b["from"], b["to"])} : #{format_weight(b["avg_weight"])} (std: #{b["std"]})#{divergence}")
    end)

    IO.puts("\nTop emotional reactions:")
    emotional
    |> Enum.take(10)
    |> Enum.each(fn b ->
      divergence = if b["std"] > 0.25, do: "  ** high divergence", else: ""
      IO.puts("  #{pad_edge(b["from"], b["to"])} : #{format_weight(b["avg_weight"])} (std: #{b["std"]})#{divergence}")
    end)

    IO.puts("")
  end

  defp show_emergent(population) do
    alias PopulationSimulator.Metrics.Aggregator

    nodes = Aggregator.emergent_nodes(population.id)

    IO.puts("\n=== Emergent Nodes: #{population.name} ===\n")

    if nodes == [] do
      IO.puts("No emergent nodes found.")
    else
      Enum.each(nodes, fn n ->
        IO.puts("  #{n["node_id"]} (#{n["actor_count"]} actors) — added after \"#{n["added_at"]}\"")
      end)
    end

    IO.puts("")
  end

  defp show_edge_history(population, edge_str) do
    alias PopulationSimulator.Metrics.Aggregator

    [from, to] = String.split(edge_str, "->")

    evolution = Aggregator.belief_evolution(population.id)

    matching = Enum.filter(evolution, fn e ->
      e["from"] == from && e["to"] == to
    end)

    IO.puts("\n=== Edge History: #{from} -> #{to} (#{population.name}) ===\n")

    if matching == [] do
      IO.puts("No data found for this edge.")
    else
      Enum.each(matching, fn e ->
        IO.puts("  #{String.pad_trailing(e["measure"] || "", 40)} | #{format_weight(e["avg_weight"])}")
      end)
    end

    IO.puts("")
  end

  defp pad_edge(from, to) do
    String.pad_trailing("#{from} -> #{to}", 30)
  end

  defp format_weight(nil), do: " -   "
  defp format_weight(w) when w >= 0, do: "+#{w}"
  defp format_weight(w), do: "#{w}"
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/sim.beliefs.ex
git commit -m "Add sim.beliefs mix task for querying belief graphs"
```

---

### Task 11: End-to-end verification

- [ ] **Step 1: Reset database**

```bash
mix ecto.reset
```

- [ ] **Step 2: Generate belief templates (requires CLAUDE_API_KEY)**

```bash
mix sim.beliefs.init
```

Expected: 8 JSON files created in `priv/data/belief_templates/`.

If CLAUDE_API_KEY is not available, create a single test template manually:

```bash
mkdir -p priv/data/belief_templates
cat > priv/data/belief_templates/middle_right.json << 'TEMPLATE'
{
  "nodes": [
    {"id": "inflation", "type": "core"},
    {"id": "employment", "type": "core"},
    {"id": "taxes", "type": "core"},
    {"id": "dollar", "type": "core"},
    {"id": "state_role", "type": "core"},
    {"id": "social_welfare", "type": "core"},
    {"id": "pensions", "type": "core"},
    {"id": "wages", "type": "core"},
    {"id": "security", "type": "core"},
    {"id": "education", "type": "core"},
    {"id": "healthcare", "type": "core"},
    {"id": "corruption", "type": "core"},
    {"id": "foreign_trade", "type": "core"},
    {"id": "utility_rates", "type": "core"},
    {"id": "private_property", "type": "core"}
  ],
  "edges": [
    {"from": "taxes", "to": "employment", "type": "causal", "weight": -0.7, "description": "More taxes reduce employment"},
    {"from": "inflation", "to": "wages", "type": "causal", "weight": -0.8, "description": "Inflation erodes wages"},
    {"from": "state_role", "to": "corruption", "type": "causal", "weight": 0.6, "description": "Bigger state means more corruption"},
    {"from": "social_welfare", "to": "employment", "type": "causal", "weight": -0.4, "description": "Welfare discourages work"},
    {"from": "foreign_trade", "to": "employment", "type": "causal", "weight": 0.5, "description": "Open trade creates jobs"},
    {"from": "dollar", "to": "inflation", "type": "causal", "weight": 0.7, "description": "Dollar rise causes inflation"},
    {"from": "utility_rates", "to": "inflation", "type": "causal", "weight": 0.3, "description": "Higher utilities push prices"},
    {"from": "private_property", "to": "employment", "type": "causal", "weight": 0.5, "description": "Property rights drive investment"},
    {"from": "inflation", "to": "anger", "type": "emotional", "weight": 0.8, "description": "Inflation makes me angry"},
    {"from": "corruption", "to": "indignation", "type": "emotional", "weight": 0.9, "description": "Corruption is outrageous"},
    {"from": "taxes", "to": "frustration", "type": "emotional", "weight": 0.7, "description": "High taxes frustrate me"},
    {"from": "dollar", "to": "anxiety", "type": "emotional", "weight": 0.6, "description": "Dollar instability worries me"},
    {"from": "security", "to": "fear", "type": "emotional", "weight": 0.5, "description": "Insecurity scares me"},
    {"from": "private_property", "to": "confidence", "type": "emotional", "weight": 0.6, "description": "Property rights give me confidence"},
    {"from": "social_welfare", "to": "resentment", "type": "emotional", "weight": 0.4, "description": "Welfare at my expense"}
  ]
}
TEMPLATE
```

Copy that template for all archetypes for testing (in production, use `mix sim.beliefs.init`):

```bash
for name in destitute_left destitute_right lower_middle_left lower_middle_right middle_left middle_right upper_left upper_right; do
  cp priv/data/belief_templates/middle_right.json "priv/data/belief_templates/${name}.json"
done
```

- [ ] **Step 3: Seed with population**

```bash
mix sim.seed --n 100 --population "Test Panel"
```

Expected: Actors, moods, and belief graphs created. Should see "Creating initial belief graphs..."

- [ ] **Step 4: Verify beliefs exist**

```bash
mix sim.beliefs --population "Test Panel"
```

Expected: Shows causal beliefs and emotional reactions with weights and std.

- [ ] **Step 5: Check emergent nodes (should be empty initially)**

```bash
mix sim.beliefs --population "Test Panel" --emergent
```

Expected: "No emergent nodes found."

- [ ] **Step 6: Run a measure (requires CLAUDE_API_KEY)**

```bash
mix sim.run --title "Aumento retenciones" --description "El gobierno aumenta las retenciones a la exportacion de soja del 33% al 40%" --population "Test Panel" --limit 5
```

Expected: 5 actors evaluated with belief updates persisted.

- [ ] **Step 7: Check beliefs after measure**

```bash
mix sim.beliefs --population "Test Panel"
```

Expected: Updated weights reflecting the measure's impact.

- [ ] **Step 8: Verify compilation is clean**

```bash
mix compile --warnings-as-errors
```

Expected: No warnings, no errors.
