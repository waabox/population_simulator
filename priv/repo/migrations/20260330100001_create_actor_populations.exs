defmodule PopulationSimulator.Repo.Migrations.CreateActorPopulations do
  use Ecto.Migration

  def change do
    create table(:actor_populations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :uuid, on_delete: :delete_all), null: false
      add :population_id, references(:populations, type: :uuid, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:actor_populations, [:actor_id, :population_id])
    create index(:actor_populations, [:population_id])
  end
end
