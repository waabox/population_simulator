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
