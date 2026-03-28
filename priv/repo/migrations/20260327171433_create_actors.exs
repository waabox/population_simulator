defmodule PopulationSimulator.Repo.Migrations.CreateActors do
  use Ecto.Migration

  def change do
    create table(:actors, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :profile, :map, null: false
      add :prompt_base, :text
      add :stratum, :string
      add :zone, :string
      add :age, :integer
      add :employment_type, :string
      add :tenure, :string
      add :political_orientation, :integer
      add :receives_benefit, :boolean, default: false
      timestamps(type: :utc_datetime)
    end

    create index(:actors, [:stratum])
    create index(:actors, [:zone])
    create index(:actors, [:employment_type])
  end
end
