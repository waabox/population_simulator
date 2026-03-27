defmodule PopulationSimulator.Repo.Migrations.CreateActors do
  use Ecto.Migration

  def change do
    create table(:actors, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :profile, :map, null: false
      add :prompt_base, :text
      add :estrato, :string
      add :zona, :string
      add :edad, :integer
      add :tipo_empleo, :string
      add :tenencia, :string
      add :orientacion_politica, :integer
      add :recibe_plan, :boolean, default: false
      timestamps(type: :utc_datetime)
    end

    create index(:actors, [:estrato])
    create index(:actors, [:zona])
    create index(:actors, [:tipo_empleo])
  end
end
