defmodule PopulationSimulator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PopulationSimulator.Repo,
      {Registry, keys: :unique, name: PopulationSimulator.ActorRegistry},
      {DynamicSupervisor, name: PopulationSimulator.Actors.PopulationSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: PopulationSimulator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
