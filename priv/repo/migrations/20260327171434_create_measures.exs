defmodule PopulationSimulator.Repo.Migrations.CreateMeasures do
  use Ecto.Migration

  def change do
    create table(:measures, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :titulo, :string, null: false
      add :descripcion, :text, null: false
      add :categoria, :string
      add :tags, {:array, :string}
      timestamps(type: :utc_datetime)
    end
  end
end
