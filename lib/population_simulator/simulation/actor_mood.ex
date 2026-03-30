defmodule PopulationSimulator.Simulation.ActorMood do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "actor_moods" do
    belongs_to :actor, PopulationSimulator.Actors.Actor, type: :binary_id
    belongs_to :decision, PopulationSimulator.Simulation.Decision, type: :binary_id
    belongs_to :measure, PopulationSimulator.Simulation.Measure, type: :binary_id
    field :economic_confidence, :integer
    field :government_trust, :integer
    field :personal_wellbeing, :integer
    field :social_anger, :integer
    field :future_outlook, :integer
    field :narrative, :string
    timestamps(type: :utc_datetime)
  end

  @mood_fields [:economic_confidence, :government_trust, :personal_wellbeing, :social_anger, :future_outlook, :narrative]

  def changeset(mood, attrs) do
    mood
    |> cast(attrs, [:actor_id, :decision_id, :measure_id | @mood_fields])
    |> validate_required([:actor_id, :economic_confidence, :government_trust, :personal_wellbeing, :social_anger, :future_outlook])
    |> validate_number(:economic_confidence, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:government_trust, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:personal_wellbeing, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:social_anger, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:future_outlook, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
  end

  def initial_from_profile(actor_id, profile) do
    government_trust = profile_trust_to_mood(profile["government_trust"])
    economic_confidence = derive_economic_confidence(profile)
    personal_wellbeing = derive_personal_wellbeing(profile)
    social_anger = derive_social_anger(government_trust, profile)
    future_outlook = derive_future_outlook(profile)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: nil,
      measure_id: nil,
      economic_confidence: economic_confidence,
      government_trust: government_trust,
      personal_wellbeing: personal_wellbeing,
      social_anger: social_anger,
      future_outlook: future_outlook,
      narrative: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  def from_llm_response(actor_id, decision_id, measure_id, mood_update) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      actor_id: actor_id,
      decision_id: decision_id,
      measure_id: measure_id,
      economic_confidence: clamp(mood_update["economic_confidence"], 1, 10),
      government_trust: clamp(mood_update["government_trust"], 1, 10),
      personal_wellbeing: clamp(mood_update["personal_wellbeing"], 1, 10),
      social_anger: clamp(mood_update["social_anger"], 1, 10),
      future_outlook: clamp(mood_update["future_outlook"], 1, 10),
      narrative: mood_update["narrative"],
      inserted_at: now,
      updated_at: now
    }
  end

  # government_trust in profile is 1.0-5.0 float, convert to 1-10 integer
  defp profile_trust_to_mood(trust) when is_number(trust) do
    round(trust * 2) |> clamp(1, 10)
  end
  defp profile_trust_to_mood(_), do: 5

  defp derive_economic_confidence(profile) do
    base = case profile["stratum"] do
      "upper" -> 8
      "upper_middle" -> 7
      "middle" -> 5
      "lower_middle" -> 4
      "low" -> 3
      "destitute" -> 2
      _ -> 5
    end

    employment_adj = case profile["employment_type"] do
      "formal_employee" -> 1
      "employer" -> 1
      "unemployed" -> -2
      "informal_employee" -> -1
      _ -> 0
    end

    clamp(base + employment_adj, 1, 10)
  end

  defp derive_personal_wellbeing(profile) do
    income = profile["income"] || 0
    basket = profile["basic_basket"] || 1

    ratio = income / max(basket, 1)

    cond do
      ratio >= 3.0 -> 8
      ratio >= 2.0 -> 7
      ratio >= 1.5 -> 6
      ratio >= 1.0 -> 5
      ratio >= 0.7 -> 3
      true -> 2
    end
  end

  defp derive_social_anger(government_trust, profile) do
    base = 11 - government_trust

    stratum_adj = case profile["stratum"] do
      "destitute" -> 1
      "low" -> 1
      "upper" -> -1
      _ -> 0
    end

    clamp(base + stratum_adj, 1, 10)
  end

  defp derive_future_outlook(profile) do
    base = case profile["inflation_expectation"] do
      "very_pessimistic" -> 2
      "pessimistic" -> 4
      "neutral" -> 5
      "optimistic" -> 7
      _ -> 5
    end

    age_adj = cond do
      (profile["age"] || 30) < 30 -> 1
      (profile["age"] || 30) > 60 -> -1
      true -> 0
    end

    clamp(base + age_adj, 1, 10)
  end

  defp clamp(val, min_v, max_v) when is_number(val), do: val |> max(min_v) |> min(max_v)
  defp clamp(_, min_v, _), do: min_v
end
