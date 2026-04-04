defmodule PopulationSimulator.Simulation.IntentionExecutor do
  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorIntention
  import Ecto.Query

  @allowed_fields ~w(employment_type employment_status income_delta has_dollars usd_savings_delta has_debt housing_type tenure has_bank_account has_credit_card)
  @max_income_ratio 0.5
  @max_active 2

  def execute_resolutions(actor_id, resolutions) when is_list(resolutions) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Enum.each(resolutions, fn resolution ->
      status = resolution["status"]
      description = resolution["description"]
      if status in ["executed", "frustrated"] do
        intention = Repo.one(from(i in ActorIntention,
          where: i.actor_id == ^actor_id and i.status == "pending",
          where: like(i.description, ^"%#{String.slice(description || "", 0, 30)}%"),
          order_by: [desc: i.inserted_at], limit: 1))
        if intention do
          Repo.update_all(from(i in ActorIntention, where: i.id == ^intention.id), set: [status: status, resolved_at: now])
          if status == "executed", do: apply_profile_effects(actor_id, intention)
        end
      end
    end)
  end

  def persist_new_intentions(actor_id, measure_id, intentions) when is_list(intentions) do
    pending_count = Repo.one(from(i in ActorIntention, where: i.actor_id == ^actor_id and i.status == "pending", select: count(i.id))) || 0
    available_slots = max(@max_active - pending_count, 0)
    intentions |> Enum.take(available_slots) |> Enum.each(fn intention ->
      current_income = load_actor_income(actor_id)
      effects = validate_profile_effects(intention["profile_effects"] || %{}, current_income)
      row = ActorIntention.new(actor_id, measure_id, intention["description"] || "", effects, intention["urgency"] || "medium")
      Repo.insert_all(ActorIntention, [row])
    end)
  end

  def expire_old_intentions(actor_id, introspection_count) do
    if introspection_count >= 2 do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.update_all(from(i in ActorIntention,
        where: i.actor_id == ^actor_id and i.status == "pending",
        where: i.inserted_at < ago(^(introspection_count * 3), "day")),
        set: [status: "expired", resolved_at: now])
    end
  end

  def load_pending(actor_id) do
    Repo.all(from(i in ActorIntention, where: i.actor_id == ^actor_id and i.status == "pending",
      order_by: [desc: i.inserted_at], limit: @max_active))
    |> Enum.map(fn i -> %{description: i.description, urgency: i.urgency, inserted_at: i.inserted_at} end)
  end

  def validate_profile_effects(effects, current_income) when is_map(effects) do
    effects |> Map.take(@allowed_fields) |> clamp_income_delta(current_income)
  end
  def validate_profile_effects(_, _), do: %{}

  defp clamp_income_delta(effects, current_income) do
    case Map.get(effects, "income_delta") do
      nil -> effects
      delta when is_number(delta) ->
        max_delta = round(current_income * @max_income_ratio)
        Map.put(effects, "income_delta", delta |> max(-max_delta) |> min(max_delta))
      _ -> Map.delete(effects, "income_delta")
    end
  end

  defp apply_profile_effects(actor_id, intention) do
    effects = Jason.decode!(intention.profile_effects)
    if map_size(effects) > 0 do
      actor = Repo.one(from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor_id))
      if actor do
        income = actor.profile["income"] || 0
        updated_profile = Enum.reduce(effects, actor.profile, fn
          {"income_delta", delta}, p when is_number(delta) -> Map.put(p, "income", max(round(income + delta), 0))
          {"usd_savings_delta", delta}, p when is_number(delta) ->
            Map.put(p, "usd_savings", max(round((p["usd_savings"] || 0) + delta), 0))
          {key, value}, p -> Map.put(p, key, value)
        end)
        Repo.update_all(from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor_id), set: [profile: updated_profile])
      end
    end
  end

  defp load_actor_income(actor_id) do
    case Repo.one(from(a in PopulationSimulator.Actors.Actor, where: a.id == ^actor_id, select: a.profile)) do
      nil -> 0
      profile -> profile["income"] || 0
    end
  end
end
