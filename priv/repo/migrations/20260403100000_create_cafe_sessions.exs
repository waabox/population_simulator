defmodule PopulationSimulator.Repo.Migrations.CreateCafeSessions do
  use Ecto.Migration

  def change do
    create table(:cafe_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :group_key, :string, null: false
      add :participant_ids, :text, null: false
      add :participant_names, :text, null: false
      add :conversation, :text, null: false
      add :conversation_summary, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:cafe_sessions, [:measure_id])
    create index(:cafe_sessions, [:group_key])

    create table(:cafe_effects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cafe_session_id, references(:cafe_sessions, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :mood_deltas, :text, null: false
      add :belief_deltas, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:cafe_effects, [:cafe_session_id])
    create index(:cafe_effects, [:actor_id])
  end
end
