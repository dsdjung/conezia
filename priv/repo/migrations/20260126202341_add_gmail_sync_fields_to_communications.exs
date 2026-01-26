defmodule Conezia.Repo.Migrations.AddGmailSyncFieldsToCommunications do
  use Ecto.Migration

  def change do
    alter table(:communications) do
      # Add subject field for email subject lines
      add :subject, :string, size: 1000

      # Add metadata field for additional info (thread_id, etc.)
      add :metadata, :map, default: %{}

      # Make entity_id nullable for communications not yet linked to an entity
      modify :entity_id, :binary_id, null: true
    end

    # Add index on external_id for deduplication lookups
    create_if_not_exists unique_index(:communications, [:external_id], where: "external_id IS NOT NULL")
  end
end
