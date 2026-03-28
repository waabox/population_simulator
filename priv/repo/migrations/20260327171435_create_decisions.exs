defmodule PopulationSimulator.Repo.Migrations.CreateDecisions do
  use Ecto.Migration

  def change do
    create table(:decisions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:actors, type: :binary_id), null: false
      add :measure_id, references(:measures, type: :binary_id), null: false
      add :agreement, :boolean
      add :intensity, :smallint
      add :reasoning, :text
      add :personal_impact, :text
      add :behavior_change, :text
      add :raw_response, :map
      add :tokens_used, :integer
      timestamps(type: :utc_datetime)
    end

    create unique_index(:decisions, [:actor_id, :measure_id])
    create index(:decisions, [:measure_id])
    create index(:decisions, [:measure_id, :agreement])
  end
end
