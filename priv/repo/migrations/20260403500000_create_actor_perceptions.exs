defmodule PopulationSimulator.Repo.Migrations.CreateActorPerceptions do
  use Ecto.Migration
  def change do
    create table(:actor_perceptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :cafe_session_id, references(:cafe_sessions, type: :binary_id, on_delete: :delete_all), null: false
      add :group_mood, :text, null: false
      add :referent_id, references(:actors, type: :binary_id, on_delete: :nilify_all)
      add :referent_influence, :text
      timestamps(type: :utc_datetime)
    end
    create index(:actor_perceptions, [:actor_id])
    create index(:actor_perceptions, [:actor_id, :measure_id])
  end
end
