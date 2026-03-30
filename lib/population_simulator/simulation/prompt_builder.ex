defmodule PopulationSimulator.Simulation.PromptBuilder do
  @moduledoc """
  Generates LLM prompts from actor profiles and economic measures.
  The prompt presents the actor as a first-person Argentine citizen
  and asks for a structured JSON decision.
  """

  def base(profile) when is_map(profile) do
    """
    Sos un ciudadano argentino con el siguiente perfil:

    DATOS PERSONALES:
    - Edad: #{profile["age"]} años | Sexo: #{humanize_sex(profile["sex"])}
    - Zona: #{humanize_zone(profile["zone"])}
    - Educación: #{humanize_education(profile["education_level"])}

    SITUACIÓN LABORAL:
    - Empleo: #{humanize_employment(profile["employment_type"])}
    #{sector_text(profile["economic_sector"])}
    - Ingreso mensual: $#{format_pesos(profile["income"])}

    SITUACIÓN DEL HOGAR:
    - Vivienda: #{humanize_tenure(profile["tenure"])} #{humanize_housing(profile["housing_type"])}
    #{housing_cost_text(profile)}
    - Miembros del hogar: #{profile["household_size"]}
    #{children_text(profile["minors_in_household"])}
    - Gastos canasta básica: $#{format_pesos(profile["basic_basket"])}/mes
    - Ahorro mensual estimado: $#{format_pesos(profile["estimated_savings"])}
    #{deficit_text(profile)}

    PERFIL FINANCIERO:
    - Estrato socioeconómico: #{humanize_stratum(profile["stratum"])}
    - Bancarizado: #{yes_no(profile["has_bank_account"])}
    - Tarjeta de crédito: #{yes_no(profile["has_credit_card"])}
    - Deuda activa: #{yes_no(profile["has_debt"])}
    - Ahorro en dólares: #{dollars_text(profile)}
    - Recibe plan/transferencia estatal: #{yes_no(profile["receives_welfare"])}

    PERFIL POLÍTICO Y ACTITUDINAL:
    - Orientación política: #{orientation_text(profile["political_orientation"])}/10 (1=estatista, 10=liberal)
    - Confianza en el gobierno: #{profile["government_trust"]}/5
    - Expectativa inflacionaria: #{humanize_expectation(profile["inflation_expectation"])}
    - Propensión al riesgo: #{profile["risk_propensity"]}
    #{crisis_memory_text(profile["crisis_memory"])}
    """
  end

  def build(profile, measure) when is_map(profile) do
    """
    #{base(profile)}

    ---

    El gobierno nacional anunció la siguiente medida económica:

    "#{measure.description}"

    Respondé ÚNICAMENTE con JSON válido. Sin texto antes ni después. Sin markdown.

    {
      "agreement": true | false (si estás de acuerdo o no),
      "intensity": <número entero del 1 al 10, donde 1=totalmente en contra y 10=totalmente a favor>,
      "reasoning": "<explicación en primera persona desde tu perfil, máximo 2 oraciones>",
      "personal_impact": "<cómo te afecta esta medida específicamente>",
      "behavior_change": "<qué harías diferente, si algo, ante esta medida>"
    }
    """
  end

  def build(profile, measure, mood_context) when is_map(profile) do
    """
    #{base(profile)}

    #{mood_section(mood_context)}

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
      }
    }
    """
  end

  # --- Humanizers ---

  defp humanize_sex("masculino"), do: "Masculino"
  defp humanize_sex("femenino"), do: "Femenino"
  defp humanize_sex(_), do: "Otro"

  defp humanize_zone("caba_north"), do: "CABA Norte (Palermo, Recoleta, Belgrano...)"
  defp humanize_zone("caba_south"), do: "CABA Sur (La Boca, Barracas, Villa Lugano...)"
  defp humanize_zone("suburbs_inner"), do: "Conurbano 1era corona (Lanús, Avellaneda, Quilmes...)"
  defp humanize_zone("suburbs_middle"), do: "Conurbano 2da corona (Lomas, Almirante Brown...)"
  defp humanize_zone("suburbs_outer"), do: "Conurbano 3era corona (La Matanza, Merlo, Moreno...)"
  defp humanize_zone(z), do: to_string(z)

  defp humanize_education("no_education"), do: "Sin instrucción"
  defp humanize_education("primary_incomplete"), do: "Primaria incompleta"
  defp humanize_education("primary_complete"), do: "Primaria completa"
  defp humanize_education("secondary_incomplete"), do: "Secundaria incompleta"
  defp humanize_education("secondary_complete"), do: "Secundaria completa"
  defp humanize_education("university_incomplete"), do: "Universitario/terciario incompleto"
  defp humanize_education("university_complete"), do: "Universitario/terciario completo"
  defp humanize_education(_), do: "Sin instrucción"

  defp humanize_employment("formal_employee"), do: "Asalariado/a formal (en blanco)"
  defp humanize_employment("informal_employee"), do: "Asalariado/a informal (en negro)"
  defp humanize_employment("self_employed"), do: "Cuentapropista / autónomo"
  defp humanize_employment("employer"), do: "Empleador / patrón"
  defp humanize_employment("unemployed"), do: "Desempleado/a"
  defp humanize_employment("inactive"), do: "Inactivo/a (jubilado, estudiante, ama de casa)"
  defp humanize_employment(e), do: to_string(e)

  defp humanize_tenure("owner"), do: "Propietario/a (sin hipoteca)"
  defp humanize_tenure("mortgage"), do: "Propietario/a con hipoteca"
  defp humanize_tenure("renter"), do: "Inquilino/a"
  defp humanize_tenure("lent"), do: "Vivienda cedida"
  defp humanize_tenure(t), do: to_string(t)

  defp humanize_housing("house"), do: "- Casa"
  defp humanize_housing("apartment"), do: "- Departamento"
  defp humanize_housing("tenement"), do: "- Pieza en inquilinato"
  defp humanize_housing("slum"), do: "- Vivienda en villa/asentamiento"
  defp humanize_housing(v), do: to_string(v)

  defp humanize_stratum("destitute"), do: "Indigente (por debajo de CBT)"
  defp humanize_stratum("low"), do: "Bajo (entre CBT y 1.5x CBT)"
  defp humanize_stratum("lower_middle"), do: "Medio-bajo"
  defp humanize_stratum("middle"), do: "Medio"
  defp humanize_stratum("upper_middle"), do: "Medio-alto"
  defp humanize_stratum("upper"), do: "Alto"
  defp humanize_stratum(e), do: to_string(e)

  defp humanize_expectation("very_pessimistic"), do: "Muy pesimista (la inflación va a subir mucho)"
  defp humanize_expectation("pessimistic"), do: "Pesimista (la inflación va a subir)"
  defp humanize_expectation("neutral"), do: "Neutro"
  defp humanize_expectation("optimistic"), do: "Optimista (la inflación va a bajar)"
  defp humanize_expectation(e), do: to_string(e)

  defp housing_cost_text(%{"tenure" => "renter", "housing_cost" => c}) when is_number(c) and c > 0 do
    "- Alquiler mensual estimado: $#{format_pesos(c)}"
  end

  defp housing_cost_text(%{"tenure" => "renter"}) do
    "- Paga alquiler"
  end

  defp housing_cost_text(%{"tenure" => "mortgage"}) do
    "- Cuota hipoteca mensual aprox.: $300.000"
  end

  defp housing_cost_text(_), do: ""

  defp deficit_text(%{"in_monthly_deficit" => "true", "estimated_savings" => a}) when is_number(a) do
    "DEFICIT MENSUAL: $#{format_pesos(abs(a))} (gastos superan ingresos)"
  end

  defp deficit_text(_), do: ""

  defp orientation_text(n) when is_integer(n) and n <= 3, do: "#{n} (centro-izquierda / kirchnerista)"
  defp orientation_text(n) when is_integer(n) and n <= 5, do: "#{n} (centro / peronismo moderado)"
  defp orientation_text(n) when is_integer(n) and n <= 7, do: "#{n} (centro-derecha / PRO)"
  defp orientation_text(n) when is_integer(n), do: "#{n} (derecha / libertario)"
  defp orientation_text(n), do: to_string(n)

  defp crisis_memory_text(%{"experienced_hyperinflation_89" => "true", "experienced_crisis_2001" => "true"}) do
    "- Memoria de crisis: vivió la hiperinflación del '89 y el corralito del 2001"
  end

  defp crisis_memory_text(%{"experienced_crisis_2001" => "true"}) do
    "- Memoria de crisis: vivió el corralito del 2001"
  end

  defp crisis_memory_text(%{"experienced_cepo_2011" => "true"}) do
    "- Memoria de crisis: recuerda el cepo cambiario de 2011 y las crisis más recientes"
  end

  defp crisis_memory_text(_) do
    "- Memoria de crisis: generación joven, no vivió personalmente las grandes crisis"
  end

  defp children_text(0), do: ""
  defp children_text(nil), do: ""
  defp children_text(1), do: "- Hijos menores en el hogar: 1"
  defp children_text(n) when is_integer(n) and n > 0, do: "- Hijos menores en el hogar: #{n}"
  defp children_text(_), do: ""

  defp sector_text("not_applicable"), do: ""
  defp sector_text(nil), do: ""
  defp sector_text(sector), do: "- Sector: #{humanize_sector(sector)}"

  defp humanize_sector("agriculture"), do: "Agricultura / ganadería"
  defp humanize_sector("fishing"), do: "Pesca"
  defp humanize_sector("mining"), do: "Minería"
  defp humanize_sector("food_beverages"), do: "Industria alimenticia"
  defp humanize_sector("textiles_footwear"), do: "Textil / calzado"
  defp humanize_sector("wood_industry"), do: "Industria maderera"
  defp humanize_sector("paper_industry"), do: "Industria del papel"
  defp humanize_sector("publishing_printing"), do: "Edición / imprenta"
  defp humanize_sector("chemical_pharmaceutical"), do: "Industria química / farmacéutica"
  defp humanize_sector("plastics_rubber"), do: "Industria del plástico / caucho"
  defp humanize_sector("non_metallic_minerals"), do: "Industria de minerales no metálicos"
  defp humanize_sector("metallurgy"), do: "Metalurgia / productos metálicos"
  defp humanize_sector("machinery_electronics"), do: "Maquinaria / equipos / electrónica"
  defp humanize_sector("automotive"), do: "Industria automotriz"
  defp humanize_sector("other_manufacturing"), do: "Otras industrias manufactureras"
  defp humanize_sector("recycling"), do: "Reciclaje"
  defp humanize_sector("utilities"), do: "Electricidad / gas / agua"
  defp humanize_sector("construction"), do: "Construcción"
  defp humanize_sector("wholesale"), do: "Comercio mayorista"
  defp humanize_sector("retail"), do: "Comercio minorista"
  defp humanize_sector("hospitality"), do: "Hotelería / gastronomía"
  defp humanize_sector("transport"), do: "Transporte / logística"
  defp humanize_sector("it_technology"), do: "Informática / tecnología"
  defp humanize_sector("communications"), do: "Comunicaciones"
  defp humanize_sector("finance_insurance"), do: "Finanzas / seguros"
  defp humanize_sector("professional_services"), do: "Servicios profesionales (abogados, contadores, etc.)"
  defp humanize_sector("business_services"), do: "Servicios empresariales"
  defp humanize_sector("research"), do: "Investigación / ciencia"
  defp humanize_sector("public_administration"), do: "Administración pública / defensa"
  defp humanize_sector("tourism"), do: "Turismo"
  defp humanize_sector("private_security"), do: "Seguridad privada"
  defp humanize_sector("building_services"), do: "Limpieza / mantenimiento de edificios"
  defp humanize_sector("education"), do: "Educación"
  defp humanize_sector("healthcare"), do: "Salud"
  defp humanize_sector("social_services"), do: "Servicios sociales"
  defp humanize_sector("culture_entertainment"), do: "Cultura / entretenimiento"
  defp humanize_sector("sports_recreation"), do: "Deportes / recreación"
  defp humanize_sector("organizations_unions"), do: "Organizaciones / sindicatos"
  defp humanize_sector("repairs"), do: "Reparaciones"
  defp humanize_sector("personal_services"), do: "Servicios personales (peluquería, lavandería, etc.)"
  defp humanize_sector("domestic_service"), do: "Servicio doméstico"
  defp humanize_sector("international_organizations"), do: "Organismos internacionales"
  defp humanize_sector(r), do: to_string(r)

  defp dollars_text(%{"has_dollars" => "true", "usd_savings" => usd}) do
    "sí (USD #{usd})"
  end

  defp dollars_text(_), do: "no"

  defp yes_no("true"), do: "sí"
  defp yes_no(true), do: "sí"
  defp yes_no(_), do: "no"

  defp format_pesos(nil), do: "0"
  defp format_pesos(n) when is_float(n), do: format_pesos(round(n))

  defp format_pesos(n) when is_integer(n) do
    n
    |> abs()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/\d{3}(?=\d)/, &(&1 <> "."))
    |> String.reverse()
    |> then(&if n < 0, do: "-" <> &1, else: &1)
  end

  defp format_pesos(n), do: to_string(n)

  defp mood_section(%{current_mood: current_mood, history: history}) do
    history_text = format_history(history)

    """
    === TU HISTORIAL RECIENTE ===
    #{history_text}

    === TU ESTADO EMOCIONAL ACTUAL ===
    Confianza económica: #{current_mood.economic_confidence}/10 | Confianza en el gobierno: #{current_mood.government_trust}/10
    Bienestar personal: #{current_mood.personal_wellbeing}/10 | Bronca social: #{current_mood.social_anger}/10 | Expectativa futura: #{current_mood.future_outlook}/10
    #{narrative_text(current_mood.narrative)}
    """
  end

  defp format_history([]), do: "Sin historial previo — esta es tu primera medida."

  defp format_history(history) do
    history
    |> Enum.map(fn entry ->
      agreement_text = if entry.agreement, do: "De acuerdo", else: "En desacuerdo"
      "- Medida \"#{entry.measure_title}\": #{agreement_text} (intensidad #{entry.intensity}/10)"
    end)
    |> Enum.join("\n")
  end

  defp narrative_text(nil), do: ""
  defp narrative_text(""), do: ""
  defp narrative_text(narrative), do: "\n\"#{narrative}\""
end
