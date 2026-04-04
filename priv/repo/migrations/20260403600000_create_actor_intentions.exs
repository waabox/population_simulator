defmodule PopulationSimulator.Repo.Migrations.CreateActorIntentions do
  use Ecto.Migration

  def change do
    create table(:actor_intentions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :measure_id, references(:measures, type: :binary_id, on_delete: :delete_all), null: false
      add :description, :text, null: false
      add :profile_effects, :text, null: false
      add :urgency, :string, null: false, default: "medium"
      add :status, :string, null: false, default: "pending"
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:actor_intentions, [:actor_id])
    create index(:actor_intentions, [:actor_id, :status])
  end
end
