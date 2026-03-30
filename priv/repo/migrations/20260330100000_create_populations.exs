defmodule PopulationSimulator.Repo.Migrations.CreatePopulations do
  use Ecto.Migration

  def change do
    create table(:populations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:populations, [:name])
  end
end
