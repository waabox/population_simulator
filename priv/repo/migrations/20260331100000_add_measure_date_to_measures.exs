defmodule PopulationSimulator.Repo.Migrations.AddMeasureDateToMeasures do
  use Ecto.Migration

  def change do
    alter table(:measures) do
      add :measure_date, :date
    end
  end
end
