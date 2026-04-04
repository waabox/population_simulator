defmodule PopulationSimulator.Simulation.EventDecayer do
  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorEvent
  import Ecto.Query

  @doc """
  Computes the decayed mood impact for a single event given how many ticks remain.

  The decay is linear: impact scales proportionally to `remaining / duration`.
  When `remaining` equals `duration` the full impact is returned. When `remaining`
  is 0 all values are 0.0.

  ## Parameters

  - `mood_impact` - map of mood dimension keys to numeric deltas.
  - `remaining` - ticks left for this event (0..duration).
  - `duration` - total lifetime of the event in ticks (must be > 0).

  ## Returns

  A new map with the same keys and linearly-decayed float values.
  """
  def decayed_impact(mood_impact, remaining, duration) when is_map(mood_impact) do
    ratio = if duration > 0, do: remaining / duration, else: 0.0
    Map.new(mood_impact, fn {key, val} -> {key, Float.round(val * ratio, 2)} end)
  end

  @doc """
  Aggregates the decayed mood impacts of all active events for an actor.

  Each event's impact is first decayed according to its remaining/duration ratio,
  then all decayed maps are merged by summing overlapping keys.

  ## Parameters

  - `events` - list of maps with `:mood_impact`, `:duration`, and `:remaining` keys.

  ## Returns

  A single map of mood dimension totals, or `%{}` when the list is empty.
  """
  def aggregate_active_impacts(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      decayed = decayed_impact(event.mood_impact, event.remaining, event.duration)
      Map.merge(acc, decayed, fn _k, v1, v2 -> Float.round(v1 + v2, 2) end)
    end)
  end

  @doc """
  Decrements `remaining` by 1 for all active events, then deactivates those
  whose `remaining` has reached 0.

  Runs two bulk updates inside the Repo — no individual row loading needed.
  """
  def tick_all do
    Repo.update_all(from(e in ActorEvent, where: e.active == true and e.remaining > 0), inc: [remaining: -1])
    Repo.update_all(from(e in ActorEvent, where: e.active == true and e.remaining <= 0), set: [active: false])
  end

  @doc """
  Loads the three most-recent active events for a given actor, decoding their
  JSON-encoded fields back to Elixir maps.

  ## Parameters

  - `actor_id` - UUID of the actor.

  ## Returns

  List of maps with `:description`, `:mood_impact`, `:profile_effects`,
  `:duration`, `:remaining`, and `:inserted_at` keys.
  """
  def load_active_events(actor_id) do
    Repo.all(
      from(e in ActorEvent,
        where: e.actor_id == ^actor_id and e.active == true,
        order_by: [desc: e.inserted_at],
        limit: 3
      )
    )
    |> Enum.map(fn event ->
      %{
        description: event.description,
        mood_impact: Jason.decode!(event.mood_impact),
        profile_effects: Jason.decode!(event.profile_effects),
        duration: event.duration,
        remaining: event.remaining,
        inserted_at: event.inserted_at
      }
    end)
  end
end
