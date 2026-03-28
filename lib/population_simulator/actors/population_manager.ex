defmodule PopulationSimulator.Actors.PopulationManager do
  @moduledoc """
  Manages the lifecycle of actor GenServers.
  Spawns actors from the database under the DynamicSupervisor
  and provides bulk operations.
  """

  alias PopulationSimulator.Actors.{Actor, ActorServer}
  alias PopulationSimulator.Repo
  import Ecto.Query

  @supervisor PopulationSimulator.Actors.PopulationSupervisor

  def spawn_all do
    actors = Repo.all(from(a in Actor, select: a))
    spawn_actors(actors)
  end

  def spawn_sample(n) do
    actors = Repo.all(from(a in Actor, order_by: fragment("RANDOM()"), limit: ^n))
    spawn_actors(actors)
  end

  def spawn_by_stratum(stratum, limit \\ nil) do
    query = from(a in Actor, where: a.stratum == ^to_string(stratum))
    query = if limit, do: from(q in query, limit: ^limit), else: query
    actors = Repo.all(query)
    spawn_actors(actors)
  end

  def shutdown_all do
    DynamicSupervisor.which_children(@supervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(@supervisor, pid)
    end)

    :ok
  end

  def count_alive do
    DynamicSupervisor.count_children(@supervisor).active
  end

  def list_actor_ids do
    Registry.select(PopulationSimulator.ActorRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # --- Private ---

  defp spawn_actors(actors) do
    results =
      Enum.map(actors, fn actor ->
        case DynamicSupervisor.start_child(@supervisor, {ActorServer, actor}) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :already_started
          {:error, reason} -> {:error, reason}
        end
      end)

    started = Enum.count(results, &(&1 == :ok))
    already = Enum.count(results, &(&1 == :already_started))
    errors = Enum.count(results, &match?({:error, _}, &1))

    {:ok, %{started: started, already_started: already, errors: errors, total: length(actors)}}
  end
end
