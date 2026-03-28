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
    canasta = CanastaFamiliar.calculate(actor)

    actor
    |> Map.merge(canasta)
    |> add_zone()
    |> add_financials()
    |> add_attitudinal_variables()
    |> add_crisis_memory()
    |> add_computed()
  end

  # --- Zone GBA ---
  # Uses aglomerado (32=CABA, 33=conurbano) + housing/income as proxy

  defp add_zone(actor) do
    zone =
      cond do
        actor.housing_type == :slum -> :suburbs_outer
        actor.is_caba and actor.housing_type == :apartment and actor.stratum in [:upper_middle, :upper] -> :caba_north
        actor.is_caba and actor.housing_type == :apartment -> :caba_south
        actor.is_caba -> :caba_south
        actor.stratum in [:low, :destitute] -> :suburbs_outer
        actor.stratum == :lower_middle -> :suburbs_middle
        true -> :suburbs_inner
      end

    Map.put(actor, :zone, zone)
  end

  # --- Financial variables ---
  # Source: BCRA Financial Inclusion 2023 + CEDLAS dollarization estimates

  @dollar_config %{
    upper: {0.88, 18_000},
    upper_middle: {0.62, 3_500},
    middle: {0.30, 900},
    lower_middle: {0.10, 200},
    low: {0.04, 60},
    destitute: {0.01, 0}
  }

  @banking_by_quintile [0.44, 0.67, 0.83, 0.92, 0.97]

  defp add_financials(actor) do
    {prob_dollar, mean_amount} = Map.get(@dollar_config, actor.stratum, {0.05, 0})
    has_dollars = rand() < prob_dollar
    quintile = stratum_to_quintile(actor.stratum)
    has_bank_account = rand() < Enum.at(@banking_by_quintile, quintile - 1)

    Map.merge(actor, %{
      has_dollars: has_dollars,
      usd_savings: if(has_dollars, do: sample_lognormal(mean_amount), else: 0),
      has_bank_account: has_bank_account,
      has_credit_card: has_bank_account and rand() < 0.68,
      has_debt: rand() < deuda_prob(actor.stratum),
      receives_welfare: receives_welfare?(actor)
    })
  end

  defp deuda_prob(:upper), do: 0.28
  defp deuda_prob(:upper_middle), do: 0.42
  defp deuda_prob(:middle), do: 0.56
  defp deuda_prob(:lower_middle), do: 0.51
  defp deuda_prob(:low), do: 0.36
  defp deuda_prob(:destitute), do: 0.22

  defp receives_welfare?(actor) do
    actor.employment_status in [:unemployed, :inactive] and
      actor.stratum in [:low, :destitute] and
      rand() < 0.58
  end

  # --- Attitudinal variables ---
  # Trust: UTDT ICG 2024 by SES
  # Orientation: calibrated with GBA ballotage 2023 results

  @base_trust %{
    upper: 2.6,
    upper_middle: 2.3,
    middle: 2.1,
    lower_middle: 2.5,
    low: 2.8,
    destitute: 3.0
  }

  @liberal_probability_by_zone %{
    caba_north: 0.74,
    caba_south: 0.49,
    suburbs_inner: 0.52,
    suburbs_middle: 0.46,
    suburbs_outer: 0.39
  }

  defp add_attitudinal_variables(actor) do
    trust =
      Map.get(@base_trust, actor.stratum, 2.5)
      |> sample_normal(0.85)
      |> clamp(1.0, 5.0)

    orientation = calculate_orientation(actor)

    expectation =
      cond do
        trust < 1.8 -> :very_pessimistic
        trust < 2.5 -> :pessimistic
        trust < 3.5 -> :neutral
        true -> :optimistic
      end

    Map.merge(actor, %{
      government_trust: Float.round(trust, 2),
      political_orientation: orientation,
      inflation_expectation: expectation,
      risk_propensity: calculate_risk(actor)
    })
  end

  defp calculate_orientation(actor) do
    base = Map.get(@liberal_probability_by_zone, actor.zone, 0.50)

    adj =
      [
        if(actor.education_level == :university_complete, do: +0.07, else: 0.0),
        if(actor.employment_type == :formal_employee and actor.stratum in [:low, :lower_middle],
          do: -0.10,
          else: 0.0
        ),
        if(actor.receives_welfare, do: -0.22, else: 0.0),
        if(actor.has_dollars, do: +0.13, else: 0.0),
        if(actor.stratum in [:upper, :upper_middle], do: +0.09, else: 0.0)
      ]
      |> Enum.sum()

    prob_liberal = clamp(base + adj, 0.05, 0.95)

    if rand() < prob_liberal do
      (6 + :rand.normal() * 1.3) |> round() |> trunc() |> clamp(6, 10)
    else
      (4 + :rand.normal() * 1.3) |> round() |> trunc() |> clamp(1, 5)
    end
  end

  defp calculate_risk(actor) do
    score =
      [
        if(actor.age < 35, do: 2, else: 0),
        if(actor.age > 55, do: -2, else: 0),
        if(actor.estimated_savings > 0, do: 1, else: -1),
        if(actor.has_dollars, do: 2, else: 0),
        if(actor.employment_type == :self_employed, do: 2, else: 0),
        if(actor.employment_type == :formal_employee, do: -1, else: 0),
        if(actor.has_debt, do: -1, else: 0)
      ]
      |> Enum.sum()

    cond do
      score >= 4 -> :high
      score >= 1 -> :medium
      score >= -1 -> :low
      true -> :very_low
    end
  end

  # --- Crisis memory ---

  defp add_crisis_memory(actor) do
    memory = %{
      experienced_hyperinflation_89: actor.age >= 38,
      experienced_crisis_2001: actor.age >= 28,
      experienced_cepo_2011: actor.age >= 22,
      experienced_lebacs_2018: actor.age >= 18,
      adult_years_in_crisis: calculate_crisis_years(actor.age)
    }

    Map.put(actor, :crisis_memory, memory)
  end

  defp calculate_crisis_years(age) do
    adult_years = max(age - 18, 0)
    round(adult_years * 0.55)
  end

  # --- Computed variables ---

  defp add_computed(actor) do
    Map.merge(actor, %{
      expense_income_ratio: safe_div(actor.total_expenses, actor.income) |> Float.round(3),
      in_monthly_deficit: actor.estimated_savings < 0,
      is_vulnerable: actor.stratum in [:destitute, :low] or actor.receives_welfare,
      has_family: actor.household_size > 1
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

  defp stratum_to_quintile(:destitute), do: 1
  defp stratum_to_quintile(:low), do: 1
  defp stratum_to_quintile(:lower_middle), do: 2
  defp stratum_to_quintile(:middle), do: 3
  defp stratum_to_quintile(:upper_middle), do: 4
  defp stratum_to_quintile(:upper), do: 5
  defp stratum_to_quintile(_), do: 3
end
