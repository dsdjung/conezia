defmodule Conezia.Repo.Migrations.CreateDeletedImports do
  use Ecto.Migration

  def change do
    create table(:deleted_imports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :external_id, :string, null: false
      add :source, :string, null: false
      add :entity_name, :string
      add :entity_email, :string

      timestamps(type: :utc_datetime_usec)
    end

    # Index for quick lookups during sync
    create index(:deleted_imports, [:user_id, :external_id])
    create index(:deleted_imports, [:user_id, :source])

    # Unique constraint to prevent duplicate entries
    create unique_index(:deleted_imports, [:user_id, :external_id, :source])
  end
end
