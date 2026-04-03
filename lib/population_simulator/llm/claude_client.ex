defmodule PopulationSimulator.LLM.ClaudeClient do
  @moduledoc """
  Wrapper for the Anthropic Messages API.
  Sends prompts and parses structured JSON responses.
  """

  @url "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"

  def complete_raw(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, Application.get_env(:population_simulator, :claude_model, "claude-haiku-4-5-20251001"))
    max_tokens = Keyword.get(opts, :max_tokens, 512)
    temperature = Keyword.get(opts, :temperature, 0.3)
    recv_timeout = Keyword.get(opts, :receive_timeout, 60_000)

    body = %{
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      messages: [%{role: "user", content: prompt}]
    }

    case Req.post(@url, json: body, headers: headers(), receive_timeout: recv_timeout) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        text_clean = text |> String.trim() |> strip_markdown()
        case Jason.decode(text_clean) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, "JSON parse error: #{text_clean}"}
        end

      {:ok, %{status: 429, body: body}} ->
        {:error, {:rate_limited, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, "API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def complete(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, Application.get_env(:population_simulator, :claude_model, "claude-haiku-4-5-20251001"))
    max_tokens = Keyword.get(opts, :max_tokens, 512)
    temperature = Keyword.get(opts, :temperature, 0.3)

    body = %{
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      messages: [%{role: "user", content: prompt}]
    }

    recv_timeout = Keyword.get(opts, :receive_timeout, 30_000)

    case Req.post(@url, json: body, headers: headers(), receive_timeout: recv_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status: 429, body: body}} ->
        {:error, {:rate_limited, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, "API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(%{"content" => [%{"text" => text} | _], "usage" => usage}) do
    text_clean = text |> String.trim() |> strip_markdown()

    case Jason.decode(text_clean) do
      {:ok, parsed} ->
        decision = %{
          agreement: parsed["agreement"],
          intensity: parsed["intensity"],
          reasoning: parsed["reasoning"],
          personal_impact: parsed["personal_impact"],
          behavior_change: parsed["behavior_change"],
          tokens_used: usage["input_tokens"] + usage["output_tokens"],
          raw_response: parsed,
          mood_update: parsed["mood_update"],
          belief_update: parsed["belief_update"]
        }

        {:ok, decision}

      {:error, _} ->
        {:error, "JSON parse error: #{text}"}
    end
  end

  defp parse_response(body), do: {:error, "Unexpected response: #{inspect(body)}"}

  defp strip_markdown(text) do
    text
    |> String.replace(~r/^```json\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end

  defp headers do
    api_key = Application.fetch_env!(:population_simulator, :claude_api_key)

    [
      {"x-api-key", api_key},
      {"anthropic-version", @version},
      {"content-type", "application/json"}
    ]
  end
end
