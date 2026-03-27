defmodule PopulationSimulator.DataPipeline.EphLoader do
  @moduledoc """
  Reads INDEC EPH microdata files and returns individuals from GBA.
  Source: https://www.indec.gob.ar → Bases de datos → Microdatos EPH
  Aglomerado 32 = CABA, 33 = Partidos del GBA (conurbano)
  """

  NimbleCSV.define(EphParser, separator: ";", escape: "\"")

  @aglomerados_gba ["32", "33"]

  def load(individual_path, hogar_path) do
    hogares = load_hogares(hogar_path)
    load_individuos(individual_path, hogares)
  end

  defp load_hogares(path) do
    path
    |> File.stream!([:trim_bom])
    |> EphParser.parse_stream(skip_headers: false)
    |> parse_with_headers()
    |> Stream.filter(&(&1["AGLOMERADO"] in @aglomerados_gba))
    |> Enum.reduce(%{}, fn row, acc ->
      key = {row["CODUSU"], row["NRO_HOGAR"]}

      hogar = %{
        tipo_vivienda: parse_vivienda(row["IV1"]),
        tenencia: parse_tenencia(row["II7"]),
        alquiler: parse_number(row["II4_1"]),
        itf: parse_number(row["ITF"]),
        n_miembros: parse_int(row["IX_TOT"]),
        tiene_compu: row["II3"] == "1",
        bienes_hogar: parse_int(row["V2"])
      }

      Map.put(acc, key, hogar)
    end)
  end

  defp load_individuos(path, hogares) do
    path
    |> File.stream!([:trim_bom])
    |> EphParser.parse_stream(skip_headers: false)
    |> parse_with_headers()
    |> Stream.filter(&(&1["AGLOMERADO"] in @aglomerados_gba))
    |> Stream.filter(&(parse_int(&1["CH06"]) >= 18))
    |> Enum.map(fn row ->
      key = {row["CODUSU"], row["NRO_HOGAR"]}
      hogar = Map.get(hogares, key, %{})
      # P47T = total personal income (all sources), better than TOT_P12 (occupation only)
      # -9 means not applicable in INDEC coding
      # For household members without personal income, use per-capita household income
      ingreso_personal = max(parse_number(row["P47T"]), 0)
      itf_hogar = hogar[:itf] || 0
      n_miembros = hogar[:n_miembros] || 1

      ingreso =
        if ingreso_personal > 0 do
          ingreso_personal
        else
          max(div(itf_hogar, max(n_miembros, 1)), 0)
        end
      aglomerado = row["AGLOMERADO"]

      %{
        codusu: row["CODUSU"],
        aglomerado: aglomerado,
        es_caba: aglomerado == "32",
        pondera: parse_int(row["PONDERA"]),
        edad: parse_int(row["CH06"]),
        sexo: parse_sexo(row["CH04"]),
        nivel_educacion: parse_educacion(row["NIVEL_ED"]),
        estado_empleo: parse_estado(row["ESTADO"]),
        tipo_empleo: parse_empleo(row["CAT_OCUP"], row["ESTADO"], row["PP07H"]),
        ingreso: ingreso,
        tipo_vivienda: hogar[:tipo_vivienda] || :desconocido,
        tenencia: hogar[:tenencia] || :otro,
        alquiler: hogar[:alquiler] || 0,
        itf: hogar[:itf] || ingreso,
        n_miembros_hogar: hogar[:n_miembros] || 1,
        tiene_compu: hogar[:tiene_compu] || false,
        bienes_hogar: hogar[:bienes_hogar] || 0
      }
    end)
  end

  # --- Parsers ---

  defp parse_vivienda("1"), do: :casa
  defp parse_vivienda("2"), do: :departamento
  defp parse_vivienda("3"), do: :inquilinato
  defp parse_vivienda("4"), do: :villa
  defp parse_vivienda(_), do: :otro

  defp parse_tenencia("1"), do: :propietario_pagado
  defp parse_tenencia("2"), do: :hipoteca
  defp parse_tenencia("3"), do: :alquiler
  defp parse_tenencia("4"), do: :cedida
  defp parse_tenencia(_), do: :otro

  defp parse_educacion("1"), do: :sin_instruccion
  defp parse_educacion("2"), do: :primaria_incompleta
  defp parse_educacion("3"), do: :primaria_completa
  defp parse_educacion("4"), do: :secundaria_incompleta
  defp parse_educacion("5"), do: :secundaria_completa
  defp parse_educacion("6"), do: :universitario_incompleto
  defp parse_educacion("7"), do: :universitario_completo
  defp parse_educacion(_), do: :sin_instruccion

  defp parse_estado("1"), do: :ocupado
  defp parse_estado("2"), do: :desocupado
  defp parse_estado("3"), do: :inactivo
  defp parse_estado(_), do: :inactivo

  defp parse_empleo("1", "1", _), do: :patron
  defp parse_empleo("2", "1", _), do: :cuentapropista
  defp parse_empleo("3", "1", "1"), do: :asalariado_formal
  defp parse_empleo("3", "1", "2"), do: :asalariado_informal
  defp parse_empleo("3", "1", _), do: :asalariado_informal
  defp parse_empleo(_, "2", _), do: :desempleado
  defp parse_empleo(_, "3", _), do: :inactivo
  defp parse_empleo(_, _, _), do: :otro

  defp parse_sexo("1"), do: :masculino
  defp parse_sexo("2"), do: :femenino
  defp parse_sexo(_), do: :otro

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
