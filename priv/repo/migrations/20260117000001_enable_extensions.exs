defmodule Conezia.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def up do
    # Case-insensitive text for emails
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    # UUID generation
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

    # Trigram for fuzzy search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Full-text search dictionaries
    execute "CREATE EXTENSION IF NOT EXISTS unaccent"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS unaccent"
    execute "DROP EXTENSION IF EXISTS pg_trgm"
    execute "DROP EXTENSION IF EXISTS \"uuid-ossp\""
    execute "DROP EXTENSION IF EXISTS citext"
  end
end
