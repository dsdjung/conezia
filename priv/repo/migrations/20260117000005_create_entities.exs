defmodule Conezia.Repo.Migrations.CreateEntities do
  use Ecto.Migration

  def change do
    create table(:entities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32, null: false
      add :name, :string, size: 255, null: false
      add :description, :text
      add :avatar_url, :string, size: 2048
      add :metadata, :map, default: %{}
      add :last_interaction_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:entities, [:owner_id])
    create index(:entities, [:owner_id, :type])
    create index(:entities, [:owner_id, :archived_at])
    create index(:entities, [:last_interaction_at])

    # Full-text search index using trigram
    execute """
    CREATE INDEX entities_name_trgm_idx ON entities USING gin (name gin_trgm_ops);
    """, """
    DROP INDEX entities_name_trgm_idx;
    """
  end
end
