defmodule PopulationSimulator.Simulation.MeasureRunner do
  @moduledoc """
  Orchestrates running an economic measure against all actors.
  Uses Task.async_stream for concurrent LLM calls with backpressure.
  """

  alias PopulationSimulator.{Repo, Actors.Actor, LLM.ClaudeClient,
                              Simulation.PromptBuilder, Simulation.Decision}
  import Ecto.Query

  def run(measure_id, opts \\ []) do
    concurrency =
      Keyword.get(
        opts,
        :concurrency,
        Application.get_env(:population_simulator, :llm_concurrency, 30)
      )

    limit = Keyword.get(opts, :limit, nil)

    measure = Repo.get!(PopulationSimulator.Simulation.Measure, measure_id)

    query = from(a in Actor, select: a)
    query = if limit, do: from(q in query, limit: ^limit), else: query
    actors = Repo.all(query)
    total = length(actors)

    IO.puts("Simulation started: #{total} actors, concurrency: #{concurrency}")
    start = System.monotonic_time(:second)

    results =
      actors
      |> Task.async_stream(
        fn actor ->
          prompt = PromptBuilder.build(actor.profile, measure)

          case ClaudeClient.complete(prompt) do
            {:ok, decision} ->
              row = Decision.from_llm_response(actor.id, measure_id, decision)
              Repo.insert_all(Decision, [row], on_conflict: :nothing, conflict_target: [:actor_id, :measure_id])
              {:ok, actor.id, decision.tokens_usados}

            {:error, reason} ->
              {:error, actor.id, reason}
          end
        end,
        max_concurrency: concurrency,
        timeout: 45_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, error: 0, tokens: 0, errors: []}, fn
        {:ok, {:ok, _, tokens}}, acc ->
          %{acc | ok: acc.ok + 1, tokens: acc.tokens + (tokens || 0)}

        {:ok, {:error, id, reason}}, acc ->
          %{acc | error: acc.error + 1, errors: [{id, reason} | acc.errors]}

        {:exit, _}, acc ->
          %{acc | error: acc.error + 1}
      end)

    elapsed = System.monotonic_time(:second) - start
    IO.puts("Completed in #{elapsed}s — OK: #{results.ok} | Errors: #{results.error} | Tokens: #{results.tokens}")

    {:ok, results}
  end
end
