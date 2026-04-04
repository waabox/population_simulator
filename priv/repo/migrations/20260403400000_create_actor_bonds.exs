defmodule PopulationSimulator.Repo.Migrations.CreateActorBonds do
  use Ecto.Migration
  def change do
    create table(:actor_bonds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_a_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_b_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :affinity, :float, null: false, default: 0.1
      add :shared_cafes, :integer, null: false, default: 1
      add :formed_at, :utc_datetime
      add :last_cafe_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end
    create unique_index(:actor_bonds, [:actor_a_id, :actor_b_id])
    create index(:actor_bonds, [:actor_a_id])
    create index(:actor_bonds, [:actor_b_id])
  end
end
