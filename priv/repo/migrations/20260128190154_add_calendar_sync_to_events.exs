defmodule Conezia.Repo.Migrations.AddCalendarSyncToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :external_id, :string, size: 512
      add :external_account_id, references(:external_accounts, type: :binary_id, on_delete: :nilify_all)
      add :sync_metadata, :map, default: %{}
      add :sync_status, :string, size: 32, default: "local_only"
      add :last_synced_at, :utc_datetime_usec
    end

    create index(:events, [:external_id])
    create index(:events, [:external_account_id])
    create unique_index(:events, [:user_id, :external_id], where: "external_id IS NOT NULL", name: :events_user_external_id_unique)
  end
end
