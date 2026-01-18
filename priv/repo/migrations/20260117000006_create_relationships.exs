defmodule Conezia.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def change do
    create table(:relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32
      add :strength, :string, size: 16, default: "regular"
      add :status, :string, size: 16, default: "active"
      add :started_at, :date
      add :health_threshold_days, :integer, default: 30
      add :notes, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:relationships, [:user_id, :entity_id])
    create index(:relationships, [:user_id, :status])
    create index(:relationships, [:entity_id])
  end
end
