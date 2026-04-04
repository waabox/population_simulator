defmodule PopulationSimulator.Repo.Migrations.CreateActorEvents do
  use Ecto.Migration
  def change do
    create table(:actor_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :description, :text, null: false
      add :mood_impact, :text, null: false
      add :profile_effects, :text, null: false
      add :duration, :integer, null: false
      add :remaining, :integer, null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end
    create index(:actor_events, [:actor_id])
    create index(:actor_events, [:actor_id, :active])
  end
end
