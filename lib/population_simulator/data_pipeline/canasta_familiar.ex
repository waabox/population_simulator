defmodule PopulationSimulator.DataPipeline.CanastaFamiliar do
  @moduledoc """
  Stratification based on INDEC methodology + RIPTE income adjustment.

  INDEC measures poverty at the household level: total household income (ITF)
  vs the household CBT. We replicate this by using household_income / AE
  for stratum classification.

  Stratum thresholds derived from INDEC socioeconomic stratification (2do sem 2025):
  - Indigencia: < $767,413 familiar → < $248k por AE
  - Pobreza no indigente: $767k-$1,396k → $248k-$452k por AE
  - Vulnerable no pobre: $1,396k-$1,760k → $452k-$570k por AE
  - Clase media baja: $1,760k-$2,201k → $570k-$712k por AE
  - Clase media consolidada: $2,201k-$7,043k → $712k-$2,279k por AE
  - Acomodados/Alta: > $7,043k → > $2,279k por AE

  Update @cbt_adult_equivalent, @cba_cbt_ratio, and @income_adjustment monthly.

  Sources:
  - CBT/CBA: https://www.indec.gob.ar/indec/web/Nivel4-Tema-4-43-149
  - RIPTE: https://www.argentina.gob.ar/trabajo/seguridadsocial/ripte
  - Poverty: INDEC Vol.9 n°237 — GBA 1er sem 2025: 7.8% indigencia, 31.5% pobreza
  - Targets 2do sem 2025: 6.3% indigencia, 28.2% pobreza
  """

  # --- Update these values monthly ---

  # CBT per adult equivalent — estimated Mar 2026
  # Feb 2026: $452,321 (+2.7% MoM) → Mar 2026 est: $465,000
  # Source: INDEC Informes técnicos Vol.10 n°59 (12/03/2026)
  @cbt_adult_equivalent 465_000

  # Income adjustment factor to bring EPH incomes to current period.
  # EPH T3 2025 (Jul-Sep 2025) → Feb 2026 (CBT reference period).
  # RIPTE wage growth alone is ~8.5%, but total household income (ITF) grew
  # faster due to transfers, pensions, and informal income catching up.
  # Calibrated empirically to match INDEC 2do sem 2025 poverty targets:
  # 6.3% indigencia, 28.2% pobreza → factor 1.45 yields 7.8% / 28.8%.
  @income_adjustment 1.45

  # Stratum thresholds per adult equivalent (derived from INDEC stratification)
  @threshold_destitute 248_000
  @threshold_low 452_000
  @threshold_lower_middle 570_000
  @threshold_middle 712_000
  @threshold_upper_middle 2_279_000

  def calculate(actor) do
    ae = adult_equivalents(actor)
    adjusted_income = round(actor.income * @income_adjustment)
    adjusted_hh_income = round((actor.household_income || actor.income) * @income_adjustment)
    basic_basket = round(@cbt_adult_equivalent * ae)
    household_income_pc = safe_div(adjusted_hh_income, ae)
    stratum = determine_stratum(actor, household_income_pc)
    housing_cost = calculate_housing(actor)

    %{
      basic_basket: basic_basket,
      housing_cost: housing_cost,
      total_expenses: basic_basket + housing_cost,
      estimated_savings: adjusted_income - basic_basket - housing_cost,
      income: adjusted_income,
      stratum: stratum,
      adult_equivalents: ae
    }
  end

  defp adult_equivalents(%{household_size: n}), do: max(n * 0.88, 1.0)

  # INDEC methodology: classify by household income per AE.
  # When household income is zero (non-response or join failure),
  # use proxy indicators to avoid misclassifying all as destitute.
  defp determine_stratum(actor, household_income_pc) do
    if household_income_pc > 0 do
      classify_stratum(household_income_pc)
    else
      estimate_stratum_from_proxy(actor)
    end
  end

  defp classify_stratum(income_pc) do
    cond do
      income_pc < @threshold_destitute -> :destitute
      income_pc < @threshold_low -> :low
      income_pc < @threshold_lower_middle -> :lower_middle
      income_pc < @threshold_middle -> :middle
      income_pc < @threshold_upper_middle -> :upper_middle
      true -> :upper
    end
  end

  # Proxy-based stratum estimation for zero-income actors.
  # Uses housing type, education level, computer ownership, and employment status
  # as socioeconomic indicators. Calibrated so that ~35% of zero-income actors
  # fall into poverty strata (destitute + low), reflecting that these actors
  # disproportionately belong to poorer households — many have missing ITF data
  # rather than truly zero household income.
  defp estimate_stratum_from_proxy(actor) do
    score = proxy_score(actor)

    cond do
      score >= 6 -> :upper_middle
      score >= 5 -> :middle
      score >= 4 -> :lower_middle
      score >= 2 -> :low
      true -> :destitute
    end
  end

  defp proxy_score(actor) do
    housing_score(actor.housing_type) +
      education_score(actor.education_level) +
      if(actor.has_computer, do: 1, else: 0) +
      employment_score(actor.employment_status)
  end

  defp housing_score(:apartment), do: 2
  defp housing_score(:house), do: 1
  defp housing_score(:slum), do: 0
  defp housing_score(:tenement), do: 0
  defp housing_score(_), do: 0

  defp education_score(:university_complete), do: 3
  defp education_score(:university_incomplete), do: 2
  defp education_score(:secondary_complete), do: 1
  defp education_score(:secondary_incomplete), do: 1
  defp education_score(_), do: 0

  defp employment_score(:inactive), do: 1
  defp employment_score(:employed), do: 1
  defp employment_score(_), do: 0

  # EPH no longer publishes rent amounts, only whether they pay rent (II4_1)
  # We estimate based on housing type
  defp calculate_housing(%{tenure: :renter, housing_type: tv}), do: reference_rent(tv)
  defp calculate_housing(%{tenure: :mortgage}), do: 300_000
  defp calculate_housing(_), do: 0

  defp reference_rent(:apartment), do: 550_000
  defp reference_rent(:house), do: 480_000
  defp reference_rent(_), do: 350_000

  defp safe_div(_, b) when b == 0, do: 0.0
  defp safe_div(a, b), do: a / b
end
