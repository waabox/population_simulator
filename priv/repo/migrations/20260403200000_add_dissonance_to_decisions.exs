defmodule PopulationSimulator.Repo.Migrations.AddDissonanceToDecisions do
  use Ecto.Migration

  def change do
    alter table(:decisions) do
      add :dissonance, :float
    end
  end
end
