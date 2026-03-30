defmodule PopulationSimulator.Repo.Migrations.CreateActorBeliefs do
  use Ecto.Migration

  def change do
    create table(:actor_beliefs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :uuid, on_delete: :delete_all), null: false
      add :decision_id, references(:decisions, type: :uuid, on_delete: :nilify_all)
      add :measure_id, references(:measures, type: :uuid, on_delete: :nilify_all)
      add :graph, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:actor_beliefs, [:actor_id, :inserted_at])
    create index(:actor_beliefs, [:decision_id])
  end
end
