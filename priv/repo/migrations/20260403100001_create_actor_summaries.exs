defmodule PopulationSimulator.Repo.Migrations.CreateActorSummaries do
  use Ecto.Migration

  def change do
    create table(:actor_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :narrative, :text, null: false
      add :self_observations, :text, null: false
      add :version, :integer, null: false, default: 1
      add :measure_id, references(:measures, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:actor_summaries, [:actor_id])
    create index(:actor_summaries, [:actor_id, :version], unique: true)
  end
end
