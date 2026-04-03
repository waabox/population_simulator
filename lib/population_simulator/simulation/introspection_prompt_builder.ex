defmodule PopulationSimulator.Simulation.IntrospectionPromptBuilder do
  @moduledoc """
  Builds the introspection prompt for autobiographical narrative generation.
  """

  def build(profile, previous_narrative, decisions, cafe_summaries, current_mood) do
    narrative_section =
      if previous_narrative && previous_narrative != "" do
        """
        === TU RELATO PERSONAL ANTERIOR ===
        #{previous_narrative}
        """
      else
        "=== PRIMERA INTROSPECCIÓN ===\nEsta es tu primera reflexión. Construí tu relato desde cero."
      end

    decisions_section =
      decisions
      |> Enum.map_join("\n", fn d ->
        status = if d.agreement, do: "Aprobaste", else: "Rechazaste"
        "- #{d.measure_title}: #{status} (intensidad #{d.intensity}/10). #{d.reasoning}"
      end)

    cafes_section =
      cafe_summaries
      |> Enum.map_join("\n", fn s -> "- #{s}" end)

    mood_section = """
    Confianza económica: #{current_mood.economic_confidence}/10
    Confianza en el gobierno: #{current_mood.government_trust}/10
    Bienestar personal: #{current_mood.personal_wellbeing}/10
    Enojo social: #{current_mood.social_anger}/10
    Perspectiva de futuro: #{current_mood.future_outlook}/10
    """

    """
    Sos un ciudadano argentino del Gran Buenos Aires. A continuación tenés tu perfil, tu historia reciente, y tus conversaciones con vecinos. Tu tarea es reflexionar sobre todo esto y reescribir tu relato personal.

    === TU PERFIL ===
    Edad: #{profile["age"]} | Sexo: #{profile["sex"]} | Estrato: #{profile["stratum"]}
    Zona: #{profile["zone"]} | Empleo: #{profile["employment_type"]}
    Educación: #{profile["education_level"]}
    Ingreso: $#{profile["income"]}

    #{narrative_section}

    === ÚLTIMAS DECISIONES ===
    #{decisions_section}

    === CONVERSACIONES CON VECINOS ===
    #{cafes_section}

    === TU HUMOR ACTUAL ===
    #{mood_section}

    === INSTRUCCIONES ===
    Reflexioná sobre lo que te pasó, qué patrones notás en tus reacciones, y reescribí tu relato personal (máximo 200 palabras). También identificá hasta 5 observaciones sobre vos mismo.

    Respondé EXCLUSIVAMENTE con JSON válido:
    {
      "narrative": "<tu relato personal actualizado, máximo 200 palabras, en primera persona>",
      "self_observations": ["<observación 1>", "<observación 2>", ...]
    }
    """
    |> String.trim()
  end
end
