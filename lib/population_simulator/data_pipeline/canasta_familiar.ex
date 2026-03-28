defmodule PopulationSimulator.DataPipeline.CanastaFamiliar do
  @moduledoc """
  Canasta Basica Total INDEC.
  Update @cbt_adult_equivalent monthly.
  Source: https://www.indec.gob.ar/indec/web/Nivel4-Tema-4-43-149
  """

  # Last published INDEC CBT value (ARS) — update monthly
  @cbt_adult_equivalent 250_000

  def calculate(actor) do
    ae = adult_equivalents(actor)
    basic_basket = round(@cbt_adult_equivalent * ae)
    income_pc = safe_div(actor.income, ae)
    stratum = classify_stratum(income_pc)
    housing_cost = calculate_housing(actor)

    %{
      basic_basket: basic_basket,
      housing_cost: housing_cost,
      total_expenses: basic_basket + housing_cost,
      estimated_savings: actor.income - basic_basket - housing_cost,
      stratum: stratum,
      adult_equivalents: ae
    }
  end

  defp adult_equivalents(%{household_size: n}), do: max(n * 0.88, 1.0)

  defp classify_stratum(income_pc) do
    cbt = @cbt_adult_equivalent

    cond do
      income_pc < cbt * 0.9 -> :destitute
      income_pc < cbt * 1.5 -> :low
      income_pc < cbt * 3.0 -> :lower_middle
      income_pc < cbt * 5.5 -> :middle
      income_pc < cbt * 11.0 -> :upper_middle
      true -> :upper
    end
  end

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
