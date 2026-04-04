defmodule PopulationSimulator.Simulation.EventPromptBuilder do
  @moduledoc "Builds per-actor prompt for generating a personal life event."

  def build(profile, measure, mood, narrative, intentions) do
    narrative_section = if narrative && narrative != "", do: "\n=== TU RELATO PERSONAL ===\n#{narrative}", else: ""
    intentions_section = if intentions && intentions != [] do
      items = Enum.map_join(intentions, "\n", fn i -> "- #{i}" end)
      "\n=== TUS INTENCIONES PENDIENTES ===\n#{items}"
    else "" end
    mood_section = if mood do
      "Confianza económica: #{mood.economic_confidence}/10\nConfianza gobierno: #{mood.government_trust}/10\nBienestar: #{mood.personal_wellbeing}/10\nEnojo social: #{mood.social_anger}/10\nPerspectiva futuro: #{mood.future_outlook}/10"
    else "" end

    """
    Sos un narrador que genera un evento de vida para un ciudadano argentino del GBA.

    === PERFIL ===
    Edad: #{profile["age"]} | Sexo: #{profile["sex"]} | Estrato: #{profile["stratum"]}
    Zona: #{profile["zone"]} | Empleo: #{profile["employment_type"]}
    Estado laboral: #{profile["employment_status"]}
    Educación: #{profile["education_level"]}
    Ingreso: $#{profile["income"]}
    Vivienda: #{profile["housing_type"]} | Tenencia: #{profile["tenure"]}
    #{narrative_section}

    === HUMOR ACTUAL ===
    #{mood_section}
    #{intentions_section}

    === MEDIDA RECIENTE ===
    #{measure.title}: #{measure.description}

    === INSTRUCCIONES ===
    A este ciudadano le pasó algo esta semana. Puede ser consecuencia directa de la medida económica, o algo de su vida personal que no tiene nada que ver (problemas laborales, familiares, de salud, inseguridad, una buena noticia, etc.). Generá un evento realista y coherente con su perfil y situación.

    Respondé EXCLUSIVAMENTE con JSON válido:
    {
      "event": "<descripción del evento en 1-2 oraciones, en tercera persona>",
      "mood_impact": {
        "economic_confidence": <float -2.0 a 2.0>,
        "government_trust": <float -2.0 a 2.0>,
        "personal_wellbeing": <float -2.0 a 2.0>,
        "social_anger": <float -2.0 a 2.0>,
        "future_outlook": <float -2.0 a 2.0>
      },
      "profile_effects": {
        <campo>: <valor>
      },
      "duration": <int 1-6, cuántas medidas dura el impacto emocional>
    }

    REGLAS:
    - mood_impact: solo incluí dimensiones que cambian. Valores entre -2.0 y 2.0.
    - profile_effects: campos permitidos: employment_type, employment_status, income_delta, has_dollars, usd_savings_delta, has_debt, housing_type, tenure, has_bank_account, has_credit_card. Podés dejar vacío {} si no cambia nada del perfil.
    - income_delta es relativo al ingreso actual (no absoluto).
    - duration: 1-2 para eventos menores, 3-4 para eventos significativos, 5-6 para eventos que cambian la vida.
    - Todo en español.
    """
    |> String.trim()
  end
end
