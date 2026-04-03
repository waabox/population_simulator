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

    case summary do
      nil -> nil
      _ ->
        %{
          narrative: summary.narrative,
          self_observations: Jason.decode!(summary.self_observations),
          cafe_summaries: cafe_summaries
        }
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
