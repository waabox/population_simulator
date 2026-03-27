defmodule PopulationSimulator.Actors.ActorServer do
  @moduledoc """
  GenServer representing a single population actor.
  Each actor holds its enriched profile and can evaluate economic measures
  by generating a prompt and calling the LLM.
  """

  use GenServer

  alias PopulationSimulator.Simulation.PromptBuilder
  alias PopulationSimulator.LLM.ClaudeClient

  # --- Public API ---

  def start_link(actor) do
    GenServer.start_link(__MODULE__, actor, name: via(actor.id))
  end

  def evaluar(actor_id, measure, timeout \\ 30_000) do
    GenServer.call(via(actor_id), {:evaluar, measure}, timeout)
  end

  def get_profile(actor_id) do
    GenServer.call(via(actor_id), :get_profile)
  end

  def alive?(actor_id) do
    case Registry.lookup(PopulationSimulator.ActorRegistry, actor_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  # --- Callbacks ---

  @impl true
  def init(actor) do
    {:ok, actor}
  end

  @impl true
  def handle_call({:evaluar, measure}, _from, actor) do
    prompt = PromptBuilder.build(actor.profile, measure)

    case ClaudeClient.complete(prompt) do
      {:ok, decision} ->
        {:reply, {:ok, decision}, actor}

      {:error, reason} ->
        {:reply, {:error, reason}, actor}
    end
  end

  def handle_call(:get_profile, _from, actor) do
    {:reply, actor, actor}
  end

  # --- Private ---

  defp via(id), do: {:via, Registry, {PopulationSimulator.ActorRegistry, id}}
end
