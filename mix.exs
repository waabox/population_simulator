defmodule PopulationSimulator.MixProject do
  use Mix.Project

  def project do
    [
      app: :population_simulator,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      compilers: Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PopulationSimulator.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.17"},
      {:req, "~> 0.5"},
      {:nimble_csv, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:faker, "~> 0.18", only: [:dev, :test]},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.1.1", sparse: "optimized", app: false, compile: false, depth: 1},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:bandit, "~> 1.5"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind population_simulator", "esbuild population_simulator"],
      "assets.deploy": ["tailwind population_simulator --minify", "esbuild population_simulator --minify", "phx.digest"]
    ]
  end
end
