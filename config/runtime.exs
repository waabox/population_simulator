import Config

config :population_simulator,
  claude_api_key: System.get_env("CLAUDE_API_KEY"),
  claude_model: System.get_env("CLAUDE_MODEL", "claude-haiku-4-5-20251001"),
  llm_concurrency: String.to_integer(System.get_env("LLM_CONCURRENCY", "30"))
