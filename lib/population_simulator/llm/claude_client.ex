defmodule PopulationSimulator.LLM.ClaudeClient do
  @moduledoc """
  Wrapper for the Anthropic Messages API.
  Sends prompts and parses structured JSON responses.
  """

  @url "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"

  def complete(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, Application.get_env(:population_simulator, :claude_model, "claude-haiku-4-5-20251001"))
    max_tokens = Keyword.get(opts, :max_tokens, 512)

    body = %{
      model: model,
      max_tokens: max_tokens,
      messages: [%{role: "user", content: prompt}]
    }

    case Req.post(@url, json: body, headers: headers()) do
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
          acuerdo: parsed["acuerdo"],
          intensidad: parsed["intensidad"],
          razon: parsed["razon"],
          impacto_personal: parsed["impacto_personal"],
          cambio_comportamiento: parsed["cambio_comportamiento"],
          tokens_usados: usage["input_tokens"] + usage["output_tokens"],
          raw_response: parsed
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
