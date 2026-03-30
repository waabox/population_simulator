defmodule PopulationSimulator.Repo.Migrations.CreateActorMoods do
  use Ecto.Migration

  def change do
    create table(:actor_moods, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :uuid, on_delete: :delete_all), null: false
      add :decision_id, references(:decisions, type: :uuid, on_delete: :nilify_all)
      add :measure_id, references(:measures, type: :uuid, on_delete: :nilify_all)
      add :economic_confidence, :integer, null: false
      add :government_trust, :integer, null: false
      add :personal_wellbeing, :integer, null: false
      add :social_anger, :integer, null: false
      add :future_outlook, :integer, null: false
      add :narrative, :text
      timestamps(type: :utc_datetime)
    end

    create index(:actor_moods, [:actor_id, :inserted_at])
    create index(:actor_moods, [:decision_id])
  end
end
