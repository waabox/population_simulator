defmodule PopulationSimulator.Simulation.BeliefGraph do
  @moduledoc """
  Functions for constructing, applying deltas, and humanizing belief graphs.
  A belief graph is a map with "nodes" and "edges" lists stored as JSON.
  """

  @core_nodes ~w(inflation employment taxes dollar state_role social_welfare pensions wages security education healthcare corruption foreign_trade utility_rates private_property)
  @max_emergent_nodes 10
  @max_total_edges 40

  def core_nodes, do: @core_nodes

  @doc """
  Calls the LLM once to determine which core nodes are relevant to a measure.
  Returns a list of node IDs (e.g., ["taxes", "employment", "wages"]).
  """
  def relevant_nodes(measure_description) do
    prompt = """
    Given this economic measure for Argentina:

    "#{measure_description}"

    From this list of concepts, return ONLY the ones directly relevant to this measure:
    #{Enum.join(@core_nodes, ", ")}

    Respond with a JSON array of strings. Nothing else. No markdown.
    Example: ["taxes", "employment", "wages"]
    """

    api_key = Application.fetch_env!(:population_simulator, :claude_api_key)
    model = Application.get_env(:population_simulator, :claude_model, "claude-haiku-4-5-20251001")

    body = %{
      model: model,
      max_tokens: 128,
      messages: [%{role: "user", content: prompt}]
    }

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post("https://api.anthropic.com/v1/messages", json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        text_clean = text |> String.trim() |> String.replace(~r/^```json\n?/, "") |> String.replace(~r/\n?```$/, "") |> String.trim()
        case Jason.decode(text_clean) do
          {:ok, list} when is_list(list) -> list
          _ -> @core_nodes
        end

      _ ->
        @core_nodes
    end
  end

  @doc """
  Filters a belief graph to only include edges that touch the given relevant nodes.
  Keeps all nodes but only edges where `from` or `to` is in the relevant set.
  """
  def filter_relevant(graph, relevant_node_ids) when is_map(graph) do
    relevant_set = MapSet.new(relevant_node_ids)

    Map.update(graph, "edges", [], fn edges ->
      Enum.filter(edges, fn e ->
        MapSet.member?(relevant_set, e["from"]) or MapSet.member?(relevant_set, e["to"])
      end)
    end)
  end

  def filter_relevant(nil, _), do: nil

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
  Dampens edge weight changes that exceed max_delta per measure.
  Compares new graph against previous graph and caps weight changes.
  """
  def apply_edge_damping(new_graph, previous_graph, max_delta) when is_map(new_graph) and is_map(previous_graph) do
    prev_map = Map.new(previous_graph["edges"] || [], fn e -> {{e["from"], e["to"], e["type"]}, e["weight"]} end)

    Map.update(new_graph, "edges", [], fn edges ->
      Enum.map(edges, fn edge ->
        key = {edge["from"], edge["to"], edge["type"]}
        case Map.get(prev_map, key) do
          nil -> edge
          prev_weight ->
            delta = edge["weight"] - prev_weight
            capped_delta = delta |> max(-max_delta) |> min(max_delta)
            %{edge | "weight" => prev_weight + capped_delta}
        end
      end)
    end)
  end

  def apply_edge_damping(new_graph, _, _), do: new_graph

  @doc """
  Removes emergent nodes that haven't been reinforced within `threshold` measures.
  Also removes all edges touching those nodes.
  `current_measure_index` is the sequential index of the current measure.
  """
  def decay_emergent_nodes(graph, current_measure_index, threshold) when is_map(graph) do
    {keep_nodes, remove_ids} = Enum.reduce(graph["nodes"] || [], {[], MapSet.new()}, fn node, {keep, remove} ->
      if node["type"] == "emergent" do
        last = node["last_reinforced"] || 0
        if current_measure_index - last > threshold do
          {keep, MapSet.put(remove, node["id"])}
        else
          {[node | keep], remove}
        end
      else
        {[node | keep], remove}
      end
    end)

    edges = Enum.reject(graph["edges"] || [], fn e ->
      MapSet.member?(remove_ids, e["from"]) or MapSet.member?(remove_ids, e["to"])
    end)

    %{graph | "nodes" => Enum.reverse(keep_nodes), "edges" => edges}
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
    existing = graph["nodes"] || []
    existing_ids = Enum.map(existing, & &1["id"]) |> MapSet.new()
    emergent_count = Enum.count(existing, &(&1["type"] == "emergent"))

    unique_new = Enum.reject(new_nodes, fn n -> MapSet.member?(existing_ids, n["id"]) end)
    slots = max(@max_emergent_nodes - emergent_count, 0)
    capped = Enum.take(unique_new, slots)

    Map.update(graph, "nodes", capped, &(&1 ++ capped))
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
    existing = graph["edges"] || []
    existing_set = MapSet.new(existing, fn e -> {e["from"], e["to"], e["type"]} end)
    unique_new = Enum.reject(new_edges, fn e ->
      MapSet.member?(existing_set, {e["from"], e["to"], e["type"]})
    end)

    slots = max(@max_total_edges - length(existing), 0)
    capped = Enum.take(unique_new, slots)
    Map.update(graph, "edges", capped, &(&1 ++ capped))
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
