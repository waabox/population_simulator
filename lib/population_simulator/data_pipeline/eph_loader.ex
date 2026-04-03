defmodule PopulationSimulator.DataPipeline.EphLoader do
  @moduledoc """
  Reads INDEC EPH microdata files and returns individuals from GBA.
  Source: https://www.indec.gob.ar → Bases de datos → Microdatos EPH
  Aglomerado 32 = CABA, 33 = Partidos del GBA (conurbano)
  """

  NimbleCSV.define(EphParser, separator: ";", escape: "\"")

  @aglomerados_gba ["32", "33"]

  def load(individual_path, hogar_path) do
    households = load_households(hogar_path)
    load_individuals(individual_path, households)
  end

  defp load_households(path) do
    raw_households =
      path
      |> File.stream!([:trim_bom])
      |> EphParser.parse_stream(skip_headers: false)
      |> parse_with_headers()
      |> Stream.filter(&(&1["AGLOMERADO"] in @aglomerados_gba))
      |> Enum.map(fn row ->
        key = {row["CODUSU"], row["NRO_HOGAR"]}

        household = %{
          housing_type: parse_housing_type(row["IV1"]),
          tenure: parse_tenure(row["II7"]),
          pays_rent: row["II4_1"] == "1",
          household_income: parse_number(row["ITF"]),
          member_count: parse_int(row["IX_TOT"]),
          minors_under_10: parse_int(row["IX_MEN10"]),
          has_computer: row["II3"] == "1",
          household_assets: parse_int(row["V2"]),
          income_decil: parse_int(row["DECCFR"])
        }

        {key, household}
      end)

    # Build median ITF by decil from responding households (DECCFR 1-10)
    decil_medians = compute_decil_medians(raw_households)

    # Impute income for non-response households (DECCFR = 0 or 12)
    raw_households
    |> Enum.reduce(%{}, fn {key, household}, acc ->
      imputed = impute_household_income(household, decil_medians)
      Map.put(acc, key, imputed)
    end)
  end

  # INDEC codes DECCFR=12 for income non-response, DECCFR=0 for missing.
  # These households have ITF=0 not because they earn nothing, but because
  # they didn't report income. We impute using the median ITF of responding
  # households, distributed proportionally across deciles.
  defp impute_household_income(%{income_decil: decil, household_income: 0} = hh, decil_medians)
       when decil == 0 or decil > 10 do
    # Assign a random decil weighted by population, then use its median
    target_decil = Enum.random(1..10)
    imputed_income = Map.get(decil_medians, target_decil, 0)
    %{hh | household_income: imputed_income}
  end

  defp impute_household_income(household, _decil_medians), do: household

  defp compute_decil_medians(raw_households) do
    raw_households
    |> Enum.filter(fn {_key, hh} -> hh.income_decil >= 1 and hh.income_decil <= 10 and hh.household_income > 0 end)
    |> Enum.group_by(fn {_key, hh} -> hh.income_decil end, fn {_key, hh} -> hh.household_income end)
    |> Enum.map(fn {decil, incomes} ->
      sorted = Enum.sort(incomes)
      median = Enum.at(sorted, div(length(sorted), 2))
      {decil, median}
    end)
    |> Map.new()
  end

  defp load_individuals(path, households) do
    path
    |> File.stream!([:trim_bom])
    |> EphParser.parse_stream(skip_headers: false)
    |> parse_with_headers()
    |> Stream.filter(&(&1["AGLOMERADO"] in @aglomerados_gba))
    |> Stream.filter(&(parse_int(&1["CH06"]) >= 18))
    |> Enum.map(fn row ->
      key = {row["CODUSU"], row["NRO_HOGAR"]}
      household = Map.get(households, key, %{})
      # P47T = total personal income (all sources), better than TOT_P12 (occupation only)
      # -9 means not applicable in INDEC coding
      # For household members without personal income, use per-capita household income
      personal_income = max(parse_number(row["P47T"]), 0)
      household_total_income = household[:household_income] || 0
      member_count = household[:member_count] || 1

      income =
        if personal_income > 0 do
          personal_income
        else
          max(div(household_total_income, max(member_count, 1)), 0)
        end
      agglomerate = row["AGLOMERADO"]

      %{
        codusu: row["CODUSU"],
        agglomerate: agglomerate,
        is_caba: agglomerate == "32",
        weight: parse_int(row["PONDERA"]),
        age: parse_int(row["CH06"]),
        sex: parse_sex(row["CH04"]),
        education_level: parse_education(row["NIVEL_ED"]),
        employment_status: parse_employment_status(row["ESTADO"]),
        employment_type: parse_employment_type(row["CAT_OCUP"], row["ESTADO"], row["PP07H"]),
        economic_sector: parse_economic_sector(row["PP04B_COD"]),
        income: income,
        housing_type: household[:housing_type] || :unknown,
        tenure: household[:tenure] || :other,
        pays_rent: household[:pays_rent] || false,
        household_income: household[:household_income] || income,
        household_size: household[:member_count] || 1,
        minors_in_household: household[:minors_under_10] || 0,
        has_computer: household[:has_computer] || false,
        household_assets: household[:household_assets] || 0
      }
    end)
  end

  # --- Parsers ---

  defp parse_housing_type("1"), do: :house
  defp parse_housing_type("2"), do: :apartment
  defp parse_housing_type("3"), do: :tenement
  defp parse_housing_type("4"), do: :slum
  defp parse_housing_type(_), do: :other

  defp parse_tenure("1"), do: :owner
  defp parse_tenure("2"), do: :mortgage
  defp parse_tenure("3"), do: :renter
  defp parse_tenure("4"), do: :lent
  defp parse_tenure(_), do: :other

  defp parse_education("1"), do: :no_education
  defp parse_education("2"), do: :primary_incomplete
  defp parse_education("3"), do: :primary_complete
  defp parse_education("4"), do: :secondary_incomplete
  defp parse_education("5"), do: :secondary_complete
  defp parse_education("6"), do: :university_incomplete
  defp parse_education("7"), do: :university_complete
  defp parse_education(_), do: :no_education

  defp parse_employment_status("1"), do: :employed
  defp parse_employment_status("2"), do: :unemployed
  defp parse_employment_status("3"), do: :inactive
  defp parse_employment_status(_), do: :inactive

  defp parse_employment_type("1", "1", _), do: :employer
  defp parse_employment_type("2", "1", _), do: :self_employed
  defp parse_employment_type("3", "1", "1"), do: :formal_employee
  defp parse_employment_type("3", "1", "2"), do: :informal_employee
  defp parse_employment_type("3", "1", _), do: :informal_employee
  defp parse_employment_type(_, "2", _), do: :unemployed
  defp parse_employment_type(_, "3", _), do: :inactive
  defp parse_employment_type(_, _, _), do: :other

  # CAES 4-digit activity code -> human-readable sector
  # Source: INDEC Clasificacion de Actividades Economicas para Encuestas Sociodemograficas
  defp parse_economic_sector("NA"), do: :not_applicable
  defp parse_economic_sector(nil), do: :not_applicable
  defp parse_economic_sector(""), do: :not_applicable

  defp parse_economic_sector(code) do
    case String.slice(code, 0, 2) do
      "01" -> :agriculture
      "02" -> :agriculture
      "03" -> :fishing
      "05" -> :mining
      "10" -> :food_beverages
      "11" -> :food_beverages
      "15" -> :textiles_footwear
      "17" -> :textiles_footwear
      "18" -> :textiles_footwear
      "19" -> :textiles_footwear
      "20" -> :wood_industry
      "21" -> :paper_industry
      "22" -> :publishing_printing
      "23" -> :chemical_pharmaceutical
      "24" -> :chemical_pharmaceutical
      "25" -> :plastics_rubber
      "26" -> :non_metallic_minerals
      "27" -> :metallurgy
      "28" -> :metallurgy
      "29" -> :machinery_electronics
      "30" -> :machinery_electronics
      "31" -> :machinery_electronics
      "32" -> :machinery_electronics
      "33" -> :machinery_electronics
      "34" -> :automotive
      "35" -> :automotive
      "36" -> :other_manufacturing
      "37" -> :recycling
      "40" -> :utilities
      "41" -> :utilities
      "45" -> :construction
      "46" -> :construction
      "47" -> :retail
      "48" -> :retail
      "49" -> :transport
      "50" -> :wholesale
      "51" -> :wholesale
      "52" -> :retail
      "55" -> :hospitality
      "56" -> :hospitality
      "60" -> :transport
      "61" -> :transport
      "62" -> :it_technology
      "63" -> :it_technology
      "64" -> :communications
      "65" -> :finance_insurance
      "66" -> :finance_insurance
      "67" -> :finance_insurance
      "69" -> :professional_services
      "70" -> :business_services
      "71" -> :business_services
      "72" -> :research
      "73" -> :business_services
      "74" -> :business_services
      "75" -> :public_administration
      "77" -> :business_services
      "78" -> :business_services
      "79" -> :tourism
      "80" -> :private_security
      "81" -> :building_services
      "82" -> :business_services
      "84" -> :public_administration
      "85" -> :education
      "86" -> :healthcare
      "87" -> :healthcare
      "88" -> :social_services
      "90" -> :culture_entertainment
      "91" -> :culture_entertainment
      "92" -> :culture_entertainment
      "93" -> :sports_recreation
      "94" -> :organizations_unions
      "95" -> :repairs
      "96" -> :personal_services
      "97" -> :domestic_service
      "99" -> :international_organizations
      _ -> :other
    end
  end

  defp parse_sex("1"), do: :male
  defp parse_sex("2"), do: :female
  defp parse_sex(_), do: :other

  defp parse_int(nil), do: 0
  defp parse_int(""), do: 0

  defp parse_int(val) do
    case Integer.parse(String.trim(val)) do
      {n, _} -> n
      :error -> 0
    end
  end

  # Handles scientific notation (e.g., "5e+05") and INDEC's -9 (not applicable)
  defp parse_number(nil), do: 0
  defp parse_number(""), do: 0
  defp parse_number("-9"), do: 0

  defp parse_number(val) do
    trimmed = String.trim(val)

    cond do
      String.contains?(trimmed, "e") or String.contains?(trimmed, "E") ->
        case Float.parse(trimmed) do
          {n, _} -> round(n)
          :error -> 0
        end

      true ->
        case Integer.parse(trimmed) do
          {n, _} -> n
          :error -> 0
        end
    end
  end

  defp parse_with_headers(stream) do
    stream
    |> Enum.to_list()
    |> case do
      [] ->
        []

      [headers | rows] ->
        Stream.map(rows, fn row ->
          headers
          |> Enum.zip(row)
          |> Map.new()
        end)
    end
  end
end
