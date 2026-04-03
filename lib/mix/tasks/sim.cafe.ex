defmodule Mix.Tasks.Sim.Cafe do
  use Mix.Task

  alias PopulationSimulator.Repo
  import Ecto.Query

  @shortdoc "Query café conversations"

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [measure_id: :string, zone: :string, actor_id: :string, limit: :integer]
      )

    limit = Keyword.get(parsed, :limit, 10)

    cond do
      actor_id = parsed[:actor_id] ->
        show_actor_cafes(actor_id, limit)

      measure_id = parsed[:measure_id] ->
        zone = parsed[:zone]
        show_measure_cafes(measure_id, zone, limit)

      true ->
        IO.puts("Usage:")
        IO.puts("  mix sim.cafe --measure-id <id> [--zone <zone>]")
        IO.puts("  mix sim.cafe --actor-id <id>")
    end
  end

  defp show_measure_cafes(measure_id, zone, limit) do
    query =
      from(cs in PopulationSimulator.Simulation.CafeSession,
        where: cs.measure_id == ^measure_id,
        order_by: [asc: cs.group_key],
        limit: ^limit
      )

    query = if zone, do: where(query, [cs], like(cs.group_key, ^"#{zone}%")), else: query

    cafes = Repo.all(query)

    Enum.each(cafes, fn cafe ->
      IO.puts("\n=== Mesa: #{cafe.group_key} ===")
      IO.puts("Resumen: #{cafe.conversation_summary}")
      IO.puts("")

      conversation = Jason.decode!(cafe.conversation)
      Enum.each(conversation, fn msg ->
        IO.puts("  #{msg["name"]}: #{msg["message"]}")
      end)
    end)

    IO.puts("\nTotal: #{length(cafes)} mesas")
  end

  defp show_actor_cafes(actor_id, limit) do
    cafes =
      Repo.all(
        from(cs in PopulationSimulator.Simulation.CafeSession,
          join: ce in PopulationSimulator.Simulation.CafeEffect,
            on: ce.cafe_session_id == cs.id,
          where: ce.actor_id == ^actor_id,
          order_by: [desc: cs.inserted_at],
          limit: ^limit,
          select: {cs, ce}
        )
      )

    Enum.each(cafes, fn {cafe, effect} ->
      IO.puts("\n=== Mesa: #{cafe.group_key} ===")
      IO.puts("Resumen: #{cafe.conversation_summary}")

      conversation = Jason.decode!(cafe.conversation)
      names = Jason.decode!(cafe.participant_names)
      _actor_name = Map.get(names, actor_id, "???")

      Enum.each(conversation, fn msg ->
        prefix = if msg["actor_id"] == actor_id, do: ">>", else: "  "
        IO.puts("#{prefix} #{msg["name"]}: #{msg["message"]}")
      end)

      mood_deltas = Jason.decode!(effect.mood_deltas)
      IO.puts("\n  Efecto en humor: #{inspect(mood_deltas)}")
    end)
  end
end
