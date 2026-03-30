import Config

config :population_simulator, PopulationSimulatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_to_accept_it_ok",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:population_simulator, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:population_simulator, ~w(--watch)]}
  ]

config :population_simulator, PopulationSimulatorWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/population_simulator_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]
