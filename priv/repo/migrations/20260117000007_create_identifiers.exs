defmodule Conezia.Repo.Migrations.CreateIdentifiers do
  use Ecto.Migration

  def change do
    create table(:identifiers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32, null: false
      add :value, :string, size: 512  # Plaintext for non-sensitive
      add :value_encrypted, :binary    # Encrypted for sensitive
      add :value_hash, :string, size: 64  # For duplicate detection
      add :label, :string, size: 64
      add :is_primary, :boolean, default: false
      add :verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:identifiers, [:entity_id])
    create index(:identifiers, [:type, :value_hash])  # For duplicate detection
    create index(:identifiers, [:entity_id, :is_primary])

    # Partial unique index for primary identifiers per type per entity
    execute """
    CREATE UNIQUE INDEX identifiers_entity_type_primary_idx
    ON identifiers (entity_id, type)
    WHERE is_primary = true;
    """, """
    DROP INDEX identifiers_entity_type_primary_idx;
    """
  end
end
