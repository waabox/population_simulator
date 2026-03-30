defmodule PopulationSimulator.Repo.Migrations.AddPopulationIdToMeasures do
  use Ecto.Migration

  def change do
    alter table(:measures) do
      add :population_id, references(:populations, type: :uuid, on_delete: :nilify_all)
    end

    create index(:measures, [:population_id])
  end
end
