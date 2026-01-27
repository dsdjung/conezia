defmodule Conezia.Repo.Migrations.DeduplicateIdentifiers do
  use Ecto.Migration

  @doc """
  Migration to:
  1. Remove duplicate identifiers (keeping the oldest/primary one)
  2. Add a unique constraint to prevent future duplicates
  """

  def up do
    # First, remove duplicates keeping the one that is primary, or oldest if none is primary
    # This uses a CTE to identify duplicates and delete all but one per group
    execute """
    WITH duplicates AS (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY entity_id, type, value_hash
               ORDER BY is_primary DESC, inserted_at ASC
             ) as row_num
      FROM identifiers
      WHERE archived_at IS NULL
    )
    DELETE FROM identifiers
    WHERE id IN (
      SELECT id FROM duplicates WHERE row_num > 1
    )
    """

    # Now add a unique index to prevent future duplicates
    # Only applies to non-archived identifiers
    execute """
    CREATE UNIQUE INDEX identifiers_entity_type_value_unique_idx
    ON identifiers (entity_id, type, value_hash)
    WHERE archived_at IS NULL;
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS identifiers_entity_type_value_unique_idx;"
  end
end
