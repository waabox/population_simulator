defmodule PopulationSimulator.Repo.Migrations.CreateDecisions do
  use Ecto.Migration

  def change do
    create table(:decisions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :uuid), null: false
      add :measure_id, references(:measures, type: :uuid), null: false
      add :acuerdo, :boolean
      add :intensidad, :smallint
      add :razon, :text
      add :impacto_personal, :text
      add :cambio_comportamiento, :text
      add :raw_response, :map
      add :tokens_usados, :integer
      timestamps(type: :utc_datetime)
    end

    create unique_index(:decisions, [:actor_id, :measure_id])
    create index(:decisions, [:measure_id])
    create index(:decisions, [:measure_id, :acuerdo])
  end
end
