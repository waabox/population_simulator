defmodule PopulationSimulator.Simulation.CafePromptBuilder do
  @moduledoc """
  Builds the group conversation prompt for a café table.
  """

  @argentine_names ~w(María Jorge Carlos Ana Laura Pedro Silvia Roberto Graciela Daniel Marta Luis)

  def build(measure, participants) do
    names = assign_names(participants)
    participant_block = Enum.map_join(participants, "\n\n", fn p -> participant_section(p, names) end)

    """
    Sos un narrador que simula una conversación entre vecinos argentinos del Gran Buenos Aires que se juntan a tomar un café después de enterarse de la siguiente medida económica:

    === MEDIDA ===
    Título: #{measure.title}
    Descripción: #{measure.description}

    === PARTICIPANTES ===
    #{participant_block}

    === INSTRUCCIONES ===
    Generá una conversación realista entre estos vecinos discutiendo la medida. Cada uno habla desde su situación personal y puede influir en los demás. La conversación debe reflejar los perfiles, las decisiones que tomaron, y su estado de ánimo actual.

    Respondé EXCLUSIVAMENTE con un JSON válido (sin markdown, sin texto extra) con esta estructura:
    {
      "conversation": [
        {"actor_id": "<uuid>", "name": "<nombre>", "message": "<lo que dice>"},
        ...
      ],
      "conversation_summary": "<resumen de 2-3 oraciones de qué se habló>",
      "effects": [
        {
          "actor_id": "<uuid>",
          "mood_deltas": {
            "economic_confidence": <float entre -1.0 y 1.0>,
            "government_trust": <float entre -1.0 y 1.0>,
            "personal_wellbeing": <float entre -1.0 y 1.0>,
            "social_anger": <float entre -1.0 y 1.0>,
            "future_outlook": <float entre -1.0 y 1.0>
          },
          "belief_deltas": {
            "modified_edges": [{"from": "<node>", "to": "<node>", "weight_delta": <float entre -0.4 y 0.4>}],
            "new_nodes": []
          }
        }
      ]
    }

    REGLAS:
    - La conversación debe tener entre 8 y 15 mensajes. Todos los participantes deben hablar al menos una vez.
    - mood_deltas: cada valor entre -1.0 y 1.0. Omití dimensiones sin cambio.
    - belief_deltas: máximo 2 modified_edges por actor. new_nodes siempre vacío.
    - effects debe tener exactamente una entrada por cada participante.
    - Todo en español rioplatense.
    """
    |> String.trim()
    |> then(fn prompt -> {prompt, names} end)
  end

  defp assign_names(participants) do
    names = Enum.shuffle(@argentine_names)

    participants
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> {p.actor_id, Enum.at(names, i, "Vecino#{i + 1}")} end)
    |> Map.new()
  end

  defp participant_section(participant, names) do
    name = Map.get(names, participant.actor_id, "Vecino")
    profile = participant.profile
    decision = participant.decision
    mood = participant.mood

    agreement_text = if decision.agreement, do: "APRUEBA", else: "RECHAZA"

    """
    --- #{name} (ID: #{participant.actor_id}) ---
    Edad: #{profile["age"]} | Sexo: #{profile["sex"]} | Estrato: #{profile["stratum"]}
    Zona: #{profile["zone"]} | Empleo: #{profile["employment_type"]}
    Educación: #{profile["education_level"]}
    Decisión sobre la medida: #{agreement_text} (intensidad #{decision.intensity}/10)
    Razón: #{decision.reasoning}
    Humor actual: confianza_económica=#{mood.economic_confidence}, confianza_gobierno=#{mood.government_trust}, bienestar=#{mood.personal_wellbeing}, enojo_social=#{mood.social_anger}, perspectiva_futuro=#{mood.future_outlook}
    """
    |> String.trim()
  end
end
