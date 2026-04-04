defmodule PopulationSimulator.Simulation.ConsciousnessLoader do
  @moduledoc """
  Loads consciousness context (narrative + observations + café summaries)
  for an actor to inject into PromptBuilder.
  """

  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.{ActorSummary, CafeSession, CafeEffect}
  import Ecto.Query

  def load(actor_id) do
    summary = load_latest_summary(actor_id)
    cafe_summaries = load_recent_cafe_summaries(actor_id, 2)
    dissonance_data = load_dissonance_data(actor_id)
    events = load_active_events(actor_id)

    case summary do
      nil ->
        if dissonance_data do
          %{narrative: nil, self_observations: [], cafe_summaries: cafe_summaries, dissonance: dissonance_data, events: events}
        else
          nil
        end
      _ ->
        %{
          narrative: summary.narrative,
          self_observations: Jason.decode!(summary.self_observations),
          cafe_summaries: cafe_summaries,
          dissonance: dissonance_data,
          events: events
        }
    end
  end

  def load_dissonance_data(actor_id) do
    recent = Repo.all(
      from(d in PopulationSimulator.Simulation.Decision,
        where: d.actor_id == ^actor_id and not is_nil(d.dissonance),
        order_by: [desc: d.inserted_at],
        limit: 3,
        select: {d.dissonance, d.agreement, d.reasoning}
      )
    )

    case recent do
      [] -> nil
      values ->
        dissonances = Enum.map(values, fn {d, _, _} -> d end)
        should_confront = PopulationSimulator.Simulation.DissonanceCalculator.should_confront?(dissonances)

        contradictions =
          if should_confront do
            values
            |> Enum.filter(fn {d, _, _} -> d > 0.4 end)
            |> Enum.map(fn {_d, agreement, reasoning} ->
              action = if agreement, do: "aprobaste", else: "rechazaste"
              "#{action}: #{reasoning}"
            end)
          else
            []
          end

        %{recent_values: dissonances, should_confront: should_confront, contradictions: contradictions}
    end
  end

  defp load_latest_summary(actor_id) do
    Repo.one(
      from(s in ActorSummary,
        where: s.actor_id == ^actor_id,
        order_by: [desc: s.version],
        limit: 1
      )
    )
  end

  defp load_active_events(actor_id) do
    PopulationSimulator.Simulation.EventDecayer.load_active_events(actor_id)
  end

  defp load_recent_cafe_summaries(actor_id, limit) do
    Repo.all(
      from(cs in CafeSession,
        join: ce in CafeEffect, on: ce.cafe_session_id == cs.id,
        where: ce.actor_id == ^actor_id,
        order_by: [desc: cs.inserted_at],
        limit: ^limit,
        select: cs.conversation_summary
      )
    )
    |> Enum.reverse()
  end
end
