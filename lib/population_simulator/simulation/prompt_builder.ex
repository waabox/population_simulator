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
    - Edad: #{profile["edad"]} años | Sexo: #{humanize_sexo(profile["sexo"])}
    - Zona: #{humanize_zona(profile["zona"])}
    - Educación: #{humanize_educacion(profile["nivel_educacion"])}

    SITUACIÓN LABORAL:
    - Empleo: #{humanize_empleo(profile["tipo_empleo"])}
    - Ingreso mensual: $#{format_pesos(profile["ingreso"])}

    SITUACIÓN DEL HOGAR:
    - Vivienda: #{humanize_tenencia(profile["tenencia"])} #{humanize_vivienda(profile["tipo_vivienda"])}
    #{vivienda_costo(profile)}
    - Miembros del hogar: #{profile["n_miembros_hogar"]}
    - Gastos canasta básica: $#{format_pesos(profile["canasta_basica"])}/mes
    - Ahorro mensual estimado: $#{format_pesos(profile["ahorro_estimado"])}
    #{deficit_text(profile)}

    PERFIL FINANCIERO:
    - Estrato socioeconómico: #{humanize_estrato(profile["estrato"])}
    - Bancarizado: #{si_no(profile["bancarizado"])}
    - Tarjeta de crédito: #{si_no(profile["tiene_tarjeta"])}
    - Deuda activa: #{si_no(profile["tiene_deuda"])}
    - Ahorro en dólares: #{dolares_text(profile)}
    - Recibe plan/transferencia estatal: #{si_no(profile["recibe_plan_social"])}

    PERFIL POLÍTICO Y ACTITUDINAL:
    - Orientación política: #{orientacion_text(profile["orientacion_politica"])}/10 (1=estatista, 10=liberal)
    - Confianza en el gobierno: #{profile["confianza_gobierno"]}/5
    - Expectativa inflacionaria: #{humanize_expectativa(profile["expectativa_inflacion"])}
    - Propensión al riesgo: #{profile["propension_riesgo"]}
    #{memoria_text(profile["memoria_crisis"])}
    """
  end

  def build(profile, measure) when is_map(profile) do
    """
    #{base(profile)}

    ---

    El gobierno nacional anunció la siguiente medida económica:

    "#{measure.descripcion}"

    Respondé ÚNICAMENTE con JSON válido. Sin texto antes ni después. Sin markdown.

    {
      "acuerdo": true | false,
      "intensidad": <número entero del 1 al 10, donde 1=totalmente en contra y 10=totalmente a favor>,
      "razon": "<explicación en primera persona desde tu perfil, máximo 2 oraciones>",
      "impacto_personal": "<cómo te afecta esta medida específicamente>",
      "cambio_comportamiento": "<qué harías diferente, si algo, ante esta medida>"
    }
    """
  end

  # --- Humanizers ---

  defp humanize_sexo("masculino"), do: "Masculino"
  defp humanize_sexo("femenino"), do: "Femenino"
  defp humanize_sexo(_), do: "Otro"

  defp humanize_zona("caba_norte"), do: "CABA Norte (Palermo, Recoleta, Belgrano...)"
  defp humanize_zona("caba_sur"), do: "CABA Sur (La Boca, Barracas, Villa Lugano...)"
  defp humanize_zona("conurbano_1era"), do: "Conurbano 1era corona (Lanús, Avellaneda, Quilmes...)"
  defp humanize_zona("conurbano_2da"), do: "Conurbano 2da corona (Lomas, Almirante Brown...)"
  defp humanize_zona("conurbano_3era"), do: "Conurbano 3era corona (La Matanza, Merlo, Moreno...)"
  defp humanize_zona(z), do: to_string(z)

  defp humanize_educacion("sin_instruccion"), do: "Sin instrucción"
  defp humanize_educacion("primaria_incompleta"), do: "Primaria incompleta"
  defp humanize_educacion("primaria_completa"), do: "Primaria completa"
  defp humanize_educacion("secundaria_incompleta"), do: "Secundaria incompleta"
  defp humanize_educacion("secundaria_completa"), do: "Secundaria completa"
  defp humanize_educacion("universitario_incompleto"), do: "Universitario/terciario incompleto"
  defp humanize_educacion("universitario_completo"), do: "Universitario/terciario completo"
  defp humanize_educacion(_), do: "Sin instrucción"

  defp humanize_empleo("asalariado_formal"), do: "Asalariado/a formal (en blanco)"
  defp humanize_empleo("asalariado_informal"), do: "Asalariado/a informal (en negro)"
  defp humanize_empleo("cuentapropista"), do: "Cuentapropista / autónomo"
  defp humanize_empleo("patron"), do: "Empleador / patrón"
  defp humanize_empleo("desempleado"), do: "Desempleado/a"
  defp humanize_empleo("inactivo"), do: "Inactivo/a (jubilado, estudiante, ama de casa)"
  defp humanize_empleo(e), do: to_string(e)

  defp humanize_tenencia("propietario_pagado"), do: "Propietario/a (sin hipoteca)"
  defp humanize_tenencia("hipoteca"), do: "Propietario/a con hipoteca"
  defp humanize_tenencia("alquiler"), do: "Inquilino/a"
  defp humanize_tenencia("cedida"), do: "Vivienda cedida"
  defp humanize_tenencia(t), do: to_string(t)

  defp humanize_vivienda("casa"), do: "- Casa"
  defp humanize_vivienda("departamento"), do: "- Departamento"
  defp humanize_vivienda("inquilinato"), do: "- Pieza en inquilinato"
  defp humanize_vivienda("villa"), do: "- Vivienda en villa/asentamiento"
  defp humanize_vivienda(v), do: to_string(v)

  defp humanize_estrato("indigente"), do: "Indigente (por debajo de CBT)"
  defp humanize_estrato("bajo"), do: "Bajo (entre CBT y 1.5x CBT)"
  defp humanize_estrato("medio_bajo"), do: "Medio-bajo"
  defp humanize_estrato("medio"), do: "Medio"
  defp humanize_estrato("medio_alto"), do: "Medio-alto"
  defp humanize_estrato("alto"), do: "Alto"
  defp humanize_estrato(e), do: to_string(e)

  defp humanize_expectativa("muy_pesimista"), do: "Muy pesimista (la inflación va a subir mucho)"
  defp humanize_expectativa("pesimista"), do: "Pesimista (la inflación va a subir)"
  defp humanize_expectativa("neutro"), do: "Neutro"
  defp humanize_expectativa("optimista"), do: "Optimista (la inflación va a bajar)"
  defp humanize_expectativa(e), do: to_string(e)

  defp vivienda_costo(%{"tenencia" => "alquiler", "alquiler" => a}) when is_number(a) and a > 0 do
    "- Alquiler mensual: $#{format_pesos(a)}"
  end

  defp vivienda_costo(%{"tenencia" => "hipoteca"}) do
    "- Cuota hipoteca mensual aprox.: $300.000"
  end

  defp vivienda_costo(_), do: ""

  defp deficit_text(%{"en_default_mensual" => "true", "ahorro_estimado" => a}) when is_number(a) do
    "DEFICIT MENSUAL: $#{format_pesos(abs(a))} (gastos superan ingresos)"
  end

  defp deficit_text(_), do: ""

  defp orientacion_text(n) when is_integer(n) and n <= 3, do: "#{n} (centro-izquierda / kirchnerista)"
  defp orientacion_text(n) when is_integer(n) and n <= 5, do: "#{n} (centro / peronismo moderado)"
  defp orientacion_text(n) when is_integer(n) and n <= 7, do: "#{n} (centro-derecha / PRO)"
  defp orientacion_text(n) when is_integer(n), do: "#{n} (derecha / libertario)"
  defp orientacion_text(n), do: to_string(n)

  defp memoria_text(%{"vivio_hiperinflacion_89" => "true", "vivio_crisis_2001" => "true"}) do
    "- Memoria de crisis: vivió la hiperinflación del '89 y el corralito del 2001"
  end

  defp memoria_text(%{"vivio_crisis_2001" => "true"}) do
    "- Memoria de crisis: vivió el corralito del 2001"
  end

  defp memoria_text(%{"vivio_cepo_2011" => "true"}) do
    "- Memoria de crisis: recuerda el cepo cambiario de 2011 y las crisis más recientes"
  end

  defp memoria_text(_) do
    "- Memoria de crisis: generación joven, no vivió personalmente las grandes crisis"
  end

  defp dolares_text(%{"tiene_dolares" => "true", "ahorro_usd" => usd}) do
    "sí (USD #{usd})"
  end

  defp dolares_text(_), do: "no"

  defp si_no("true"), do: "sí"
  defp si_no(true), do: "sí"
  defp si_no(_), do: "no"

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
end
