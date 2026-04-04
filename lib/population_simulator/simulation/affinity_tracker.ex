defmodule PopulationSimulator.Simulation.AffinityTracker do
  alias PopulationSimulator.Repo
  alias PopulationSimulator.Simulation.ActorBond
  import Ecto.Query

  @affinity_increment 0.15
  @max_affinity 1.0
  @formation_threshold 3
  @decay_rate 0.1
  @max_bonds_per_actor 10

  def update_from_cafe(table_actor_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    pairs = pairs_from_table(table_actor_ids)
    Enum.each(pairs, fn {a_id, b_id} -> upsert_bond(a_id, b_id, now) end)
  end

  def decay_inactive_bonds(_current_measure_id) do
    all_bonds = Repo.all(from(b in ActorBond))
    Enum.each(all_bonds, fn bond ->
      new_affinity = Float.round(bond.affinity - @decay_rate, 2)
      if new_affinity <= 0 do
        Repo.delete(bond)
      else
        Repo.update_all(from(b in ActorBond, where: b.id == ^bond.id), set: [affinity: new_affinity])
      end
    end)
  end

  def load_bonds_for_actor(actor_id) do
    Repo.all(from(b in ActorBond,
      where: (b.actor_a_id == ^actor_id or b.actor_b_id == ^actor_id) and not is_nil(b.formed_at),
      select: %{
        partner_id: fragment("CASE WHEN ? = ? THEN ? ELSE ? END", b.actor_a_id, ^actor_id, b.actor_b_id, b.actor_a_id),
        affinity: b.affinity, shared_cafes: b.shared_cafes
      }
    ))
  end

  def load_bonds_between(actor_ids) do
    pairs = pairs_from_table(actor_ids)
    Enum.flat_map(pairs, fn {a_id, b_id} ->
      case Repo.one(from(b in ActorBond, where: b.actor_a_id == ^a_id and b.actor_b_id == ^b_id and not is_nil(b.formed_at))) do
        nil -> []
        bond -> [{a_id, b_id, bond.shared_cafes}]
      end
    end)
  end

  def pairs_from_table(actor_ids) do
    sorted = Enum.sort(actor_ids)
    for {a, i} <- Enum.with_index(sorted), b <- Enum.slice(sorted, (i + 1)..-1//1), do: {a, b}
  end

  defp upsert_bond(a_id, b_id, now) do
    a_count = bond_count(a_id)
    b_count = bond_count(b_id)
    existing = Repo.one(from(b in ActorBond, where: b.actor_a_id == ^a_id and b.actor_b_id == ^b_id))

    case existing do
      nil ->
        if a_count < @max_bonds_per_actor and b_count < @max_bonds_per_actor do
          Repo.insert_all(ActorBond, [%{
            id: Ecto.UUID.generate(), actor_a_id: a_id, actor_b_id: b_id,
            affinity: 0.1, shared_cafes: 1, formed_at: nil, last_cafe_at: now,
            inserted_at: now, updated_at: now
          }], on_conflict: :nothing)
        end
      bond ->
        new_affinity = min(bond.affinity + @affinity_increment, @max_affinity)
        new_shared = bond.shared_cafes + 1
        formed = if new_shared >= @formation_threshold and is_nil(bond.formed_at), do: now, else: bond.formed_at
        Repo.update_all(from(b in ActorBond, where: b.id == ^bond.id),
          set: [affinity: Float.round(new_affinity, 2), shared_cafes: new_shared,
                formed_at: formed, last_cafe_at: now, updated_at: now])
    end
  end

  defp bond_count(actor_id) do
    Repo.one(from(b in ActorBond, where: b.actor_a_id == ^actor_id or b.actor_b_id == ^actor_id, select: count(b.id))) || 0
  end
end
