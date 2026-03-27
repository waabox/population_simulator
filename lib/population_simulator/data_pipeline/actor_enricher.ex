defmodule PopulationSimulator.DataPipeline.ActorEnricher do
  @moduledoc """
  Enriches EPH actors with attitudinal and financial synthetic variables.

  Calibration sources:
  - Political orientation: GBA ballotage 2023 results
  - Dollar holdings: BCRA + CEDLAS estimates
  - Banking: BCRA Financial Inclusion Report 2023
  - Government trust: UTDT Confidence Index 2024
  - Attitudes: Latinobarometro 2023 Argentina
  """

  alias PopulationSimulator.DataPipeline.CanastaFamiliar

  def enrich(actor) do
    canasta = CanastaFamiliar.calcular(actor)

    actor
    |> Map.merge(canasta)
    |> add_zona()
    |> add_financials()
    |> add_actitudinales()
    |> add_memoria_crisis()
    |> add_computed()
  end

  # --- Zona GBA ---
  # Uses aglomerado (32=CABA, 33=conurbano) + housing/income as proxy

  defp add_zona(actor) do
    zona =
      cond do
        actor.tipo_vivienda == :villa -> :conurbano_3era
        actor.es_caba and actor.tipo_vivienda == :departamento and actor.estrato in [:medio_alto, :alto] -> :caba_norte
        actor.es_caba and actor.tipo_vivienda == :departamento -> :caba_sur
        actor.es_caba -> :caba_sur
        actor.estrato in [:bajo, :indigente] -> :conurbano_3era
        actor.estrato == :medio_bajo -> :conurbano_2da
        true -> :conurbano_1era
      end

    Map.put(actor, :zona, zona)
  end

  # --- Financial variables ---
  # Source: BCRA Financial Inclusion 2023 + CEDLAS dollarization estimates

  @dolar_config %{
    alto: {0.88, 18_000},
    medio_alto: {0.62, 3_500},
    medio: {0.30, 900},
    medio_bajo: {0.10, 200},
    bajo: {0.04, 60},
    indigente: {0.01, 0}
  }

  @bancarizacion_quintil [0.44, 0.67, 0.83, 0.92, 0.97]

  defp add_financials(actor) do
    {prob_dolar, monto_medio} = Map.get(@dolar_config, actor.estrato, {0.05, 0})
    tiene_dolares = rand() < prob_dolar
    quintil = estrato_a_quintil(actor.estrato)
    bancarizado = rand() < Enum.at(@bancarizacion_quintil, quintil - 1)

    Map.merge(actor, %{
      tiene_dolares: tiene_dolares,
      ahorro_usd: if(tiene_dolares, do: sample_lognormal(monto_medio), else: 0),
      bancarizado: bancarizado,
      tiene_tarjeta: bancarizado and rand() < 0.68,
      tiene_deuda: rand() < deuda_prob(actor.estrato),
      recibe_plan_social: plan_social?(actor)
    })
  end

  defp deuda_prob(:alto), do: 0.28
  defp deuda_prob(:medio_alto), do: 0.42
  defp deuda_prob(:medio), do: 0.56
  defp deuda_prob(:medio_bajo), do: 0.51
  defp deuda_prob(:bajo), do: 0.36
  defp deuda_prob(:indigente), do: 0.22

  defp plan_social?(actor) do
    actor.estado_empleo in [:desocupado, :inactivo] and
      actor.estrato in [:bajo, :indigente] and
      rand() < 0.58
  end

  # --- Attitudinal variables ---
  # Trust: UTDT ICG 2024 by SES
  # Orientation: calibrated with GBA ballotage 2023 results

  @confianza_base %{
    alto: 2.6,
    medio_alto: 2.3,
    medio: 2.1,
    medio_bajo: 2.5,
    bajo: 2.8,
    indigente: 3.0
  }

  @prob_liberal_zona %{
    caba_norte: 0.74,
    caba_sur: 0.49,
    conurbano_1era: 0.52,
    conurbano_2da: 0.46,
    conurbano_3era: 0.39
  }

  defp add_actitudinales(actor) do
    confianza =
      Map.get(@confianza_base, actor.estrato, 2.5)
      |> sample_normal(0.85)
      |> clamp(1.0, 5.0)

    orientacion = calcular_orientacion(actor)

    expectativa =
      cond do
        confianza < 1.8 -> :muy_pesimista
        confianza < 2.5 -> :pesimista
        confianza < 3.5 -> :neutro
        true -> :optimista
      end

    Map.merge(actor, %{
      confianza_gobierno: Float.round(confianza, 2),
      orientacion_politica: orientacion,
      expectativa_inflacion: expectativa,
      propension_riesgo: calcular_riesgo(actor)
    })
  end

  defp calcular_orientacion(actor) do
    base = Map.get(@prob_liberal_zona, actor.zona, 0.50)

    adj =
      [
        if(actor.nivel_educacion == :universitario_completo, do: +0.07, else: 0.0),
        if(actor.tipo_empleo == :asalariado_formal and actor.estrato in [:bajo, :medio_bajo],
          do: -0.10,
          else: 0.0
        ),
        if(actor.recibe_plan_social, do: -0.22, else: 0.0),
        if(actor.tiene_dolares, do: +0.13, else: 0.0),
        if(actor.estrato in [:alto, :medio_alto], do: +0.09, else: 0.0)
      ]
      |> Enum.sum()

    prob_liberal = clamp(base + adj, 0.05, 0.95)

    if rand() < prob_liberal do
      (6 + :rand.normal() * 1.3) |> round() |> trunc() |> clamp(6, 10)
    else
      (4 + :rand.normal() * 1.3) |> round() |> trunc() |> clamp(1, 5)
    end
  end

  defp calcular_riesgo(actor) do
    score =
      [
        if(actor.edad < 35, do: 2, else: 0),
        if(actor.edad > 55, do: -2, else: 0),
        if(actor.ahorro_estimado > 0, do: 1, else: -1),
        if(actor.tiene_dolares, do: 2, else: 0),
        if(actor.tipo_empleo == :cuentapropista, do: 2, else: 0),
        if(actor.tipo_empleo == :asalariado_formal, do: -1, else: 0),
        if(actor.tiene_deuda, do: -1, else: 0)
      ]
      |> Enum.sum()

    cond do
      score >= 4 -> :alto
      score >= 1 -> :medio
      score >= -1 -> :bajo
      true -> :muy_bajo
    end
  end

  # --- Crisis memory ---

  defp add_memoria_crisis(actor) do
    memoria = %{
      vivio_hiperinflacion_89: actor.edad >= 38,
      vivio_crisis_2001: actor.edad >= 28,
      vivio_cepo_2011: actor.edad >= 22,
      vivio_lebacs_2018: actor.edad >= 18,
      anios_adulto_en_crisis: calcular_anios_crisis(actor.edad)
    }

    Map.put(actor, :memoria_crisis, memoria)
  end

  defp calcular_anios_crisis(edad) do
    anios_adulto = max(edad - 18, 0)
    round(anios_adulto * 0.55)
  end

  # --- Computed variables ---

  defp add_computed(actor) do
    Map.merge(actor, %{
      ratio_gasto_ingreso: safe_div(actor.total_gastos, actor.ingreso) |> Float.round(3),
      en_default_mensual: actor.ahorro_estimado < 0,
      clase_vulnerable: actor.estrato in [:indigente, :bajo] or actor.recibe_plan_social,
      tiene_familia: actor.n_miembros_hogar > 1
    })
  end

  # --- Statistical helpers ---

  defp rand, do: :rand.uniform()

  defp sample_normal(mean, std) do
    u1 = max(:rand.uniform(), 1.0e-10)
    u2 = :rand.uniform()
    mean + std * :math.sqrt(-2 * :math.log(u1)) * :math.cos(2 * :math.pi() * u2)
  end

  defp sample_lognormal(mean) when mean <= 0, do: 0

  defp sample_lognormal(mean) do
    sigma = 0.8
    mu = :math.log(mean) - sigma * sigma / 2
    :math.exp(mu + sigma * sample_normal(0, 1)) |> round() |> max(0)
  end

  defp clamp(val, min_v, max_v) when is_float(val) do
    val |> max(min_v * 1.0) |> min(max_v * 1.0)
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)

  defp safe_div(_, b) when b == 0, do: 0.0
  defp safe_div(a, b), do: a / b

  defp estrato_a_quintil(:indigente), do: 1
  defp estrato_a_quintil(:bajo), do: 1
  defp estrato_a_quintil(:medio_bajo), do: 2
  defp estrato_a_quintil(:medio), do: 3
  defp estrato_a_quintil(:medio_alto), do: 4
  defp estrato_a_quintil(:alto), do: 5
  defp estrato_a_quintil(_), do: 3
end
