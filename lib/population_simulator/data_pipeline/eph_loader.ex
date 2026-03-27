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
        paga_alquiler: row["II4_1"] == "1",
        itf: parse_number(row["ITF"]),
        n_miembros: parse_int(row["IX_TOT"]),
        menores_10: parse_int(row["IX_MEN10"]),
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
        rama_actividad: parse_rama(row["PP04B_COD"]),
        ingreso: ingreso,
        tipo_vivienda: hogar[:tipo_vivienda] || :desconocido,
        tenencia: hogar[:tenencia] || :otro,
        paga_alquiler: hogar[:paga_alquiler] || false,
        itf: hogar[:itf] || ingreso,
        n_miembros_hogar: hogar[:n_miembros] || 1,
        menores_hogar: hogar[:menores_10] || 0,
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

  # CAES 4-digit activity code -> human-readable sector
  # Source: INDEC Clasificacion de Actividades Economicas para Encuestas Sociodemograficas
  defp parse_rama("NA"), do: :no_aplica
  defp parse_rama(nil), do: :no_aplica
  defp parse_rama(""), do: :no_aplica

  defp parse_rama(code) do
    case String.slice(code, 0, 2) do
      "01" -> :agricultura
      "02" -> :agricultura
      "03" -> :pesca
      "05" -> :mineria
      "10" -> :alimentos_bebidas
      "11" -> :alimentos_bebidas
      "15" -> :textil_calzado
      "17" -> :textil_calzado
      "18" -> :textil_calzado
      "19" -> :textil_calzado
      "20" -> :industria_madera
      "21" -> :industria_papel
      "22" -> :edicion_imprenta
      "23" -> :industria_quimica
      "24" -> :industria_quimica
      "25" -> :industria_plastico
      "26" -> :industria_minerales
      "27" -> :metalurgia
      "28" -> :metalurgia
      "29" -> :maquinaria_equipos
      "30" -> :maquinaria_equipos
      "31" -> :maquinaria_equipos
      "32" -> :maquinaria_equipos
      "33" -> :maquinaria_equipos
      "34" -> :automotriz
      "35" -> :automotriz
      "36" -> :otras_industrias
      "37" -> :reciclaje
      "40" -> :electricidad_gas_agua
      "41" -> :electricidad_gas_agua
      "45" -> :construccion
      "46" -> :construccion
      "47" -> :comercio_minorista
      "48" -> :comercio_minorista
      "49" -> :transporte
      "50" -> :comercio_mayorista
      "51" -> :comercio_mayorista
      "52" -> :comercio_minorista
      "55" -> :hoteleria_gastronomia
      "56" -> :hoteleria_gastronomia
      "60" -> :transporte
      "61" -> :transporte
      "62" -> :informatica_tecnologia
      "63" -> :informatica_tecnologia
      "64" -> :comunicaciones
      "65" -> :finanzas_seguros
      "66" -> :finanzas_seguros
      "67" -> :finanzas_seguros
      "69" -> :servicios_profesionales
      "70" -> :servicios_empresariales
      "71" -> :servicios_empresariales
      "72" -> :investigacion
      "73" -> :servicios_empresariales
      "74" -> :servicios_empresariales
      "75" -> :administracion_publica
      "77" -> :servicios_empresariales
      "78" -> :servicios_empresariales
      "79" -> :turismo
      "80" -> :seguridad_privada
      "81" -> :servicios_edificios
      "82" -> :servicios_empresariales
      "84" -> :administracion_publica
      "85" -> :educacion
      "86" -> :salud
      "87" -> :salud
      "88" -> :servicios_sociales
      "90" -> :cultura_entretenimiento
      "91" -> :cultura_entretenimiento
      "92" -> :cultura_entretenimiento
      "93" -> :deportes_recreacion
      "94" -> :organizaciones_sindicatos
      "95" -> :reparaciones
      "96" -> :servicios_personales
      "97" -> :servicio_domestico
      "99" -> :organismos_internacionales
      _ -> :otro
    end
  end

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
