defmodule PopulationSimulator.DataPipeline.CanastaFamiliar do
  @moduledoc """
  Canasta Basica Total INDEC.
  Update @cbt_adulto_equivalente monthly.
  Source: https://www.indec.gob.ar/indec/web/Nivel4-Tema-4-43-149
  """

  # Last published INDEC CBT value (ARS) — update monthly
  @cbt_adulto_equivalente 250_000

  def calcular(actor) do
    ae = adultos_equivalentes(actor)
    canasta = round(@cbt_adulto_equivalente * ae)
    ingreso_pc = safe_div(actor.ingreso, ae)
    estrato = clasificar_estrato(ingreso_pc)
    costo_vivienda = calcular_vivienda(actor)

    %{
      canasta_basica: canasta,
      costo_vivienda: costo_vivienda,
      total_gastos: canasta + costo_vivienda,
      ahorro_estimado: actor.ingreso - canasta - costo_vivienda,
      estrato: estrato,
      adultos_eq: ae
    }
  end

  defp adultos_equivalentes(%{n_miembros_hogar: n}), do: max(n * 0.88, 1.0)

  defp clasificar_estrato(ingreso_pc) do
    cbt = @cbt_adulto_equivalente

    cond do
      ingreso_pc < cbt * 0.9 -> :indigente
      ingreso_pc < cbt * 1.5 -> :bajo
      ingreso_pc < cbt * 3.0 -> :medio_bajo
      ingreso_pc < cbt * 5.5 -> :medio
      ingreso_pc < cbt * 11.0 -> :medio_alto
      true -> :alto
    end
  end

  # EPH no longer publishes rent amounts, only whether they pay rent (II4_1)
  # We estimate based on housing type
  defp calcular_vivienda(%{tenencia: :alquiler, tipo_vivienda: tv}), do: alquiler_ref(tv)
  defp calcular_vivienda(%{tenencia: :hipoteca}), do: 300_000
  defp calcular_vivienda(_), do: 0

  defp alquiler_ref(:departamento), do: 550_000
  defp alquiler_ref(:casa), do: 480_000
  defp alquiler_ref(_), do: 350_000

  defp safe_div(_, b) when b == 0, do: 0.0
  defp safe_div(a, b), do: a / b
end
