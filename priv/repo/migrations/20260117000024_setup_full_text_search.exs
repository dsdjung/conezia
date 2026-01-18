defmodule Conezia.Repo.Migrations.SetupFullTextSearch do
  use Ecto.Migration

  def up do
    # Create custom text search configuration
    execute "CREATE TEXT SEARCH CONFIGURATION conezia_search (COPY = simple);"

    execute """
    ALTER TEXT SEARCH CONFIGURATION conezia_search
      ALTER MAPPING FOR hword, hword_part, word
      WITH unaccent, simple;
    """

    # Add tsvector column to entities for full-text search
    execute """
    ALTER TABLE entities ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      setweight(to_tsvector('conezia_search', coalesce(name, '')), 'A') ||
      setweight(to_tsvector('conezia_search', coalesce(description, '')), 'B')
    ) STORED;
    """

    execute "CREATE INDEX entities_search_idx ON entities USING gin(search_vector);"
  end

  def down do
    execute "DROP INDEX IF EXISTS entities_search_idx;"
    execute "ALTER TABLE entities DROP COLUMN IF EXISTS search_vector;"
    execute "DROP TEXT SEARCH CONFIGURATION IF EXISTS conezia_search;"
  end
end
