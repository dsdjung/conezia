defmodule Conezia.Repo.Migrations.BackfillSelfEntities do
  use Ecto.Migration

  def up do
    # Create a self entity for each user that doesn't already have one
    execute """
    INSERT INTO entities (id, type, name, owner_id, is_self, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'person', COALESCE(u.name, u.email), u.id, true, NOW(), NOW()
    FROM users u
    WHERE NOT EXISTS (
      SELECT 1 FROM entities e WHERE e.owner_id = u.id AND e.is_self = true
    )
    """
  end

  def down do
    execute "DELETE FROM entities WHERE is_self = true"
  end
end
