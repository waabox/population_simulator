import Config

config :population_simulator,
  claude_api_key: System.get_env("CLAUDE_API_KEY"),
  claude_model: System.get_env("CLAUDE_MODEL", "claude-haiku-4-5-20251001"),
  llm_concurrency: String.to_integer(System.get_env("LLM_CONCURRENCY", "30"))

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE not set"

  config :population_simulator, PopulationSimulatorWeb.Endpoint,
    secret_key_base: secret_key_base
end
