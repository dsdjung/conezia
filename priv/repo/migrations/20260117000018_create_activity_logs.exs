defmodule Conezia.Repo.Migrations.CreateActivityLogs do
  use Ecto.Migration

  def change do
    create table(:activity_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :action, :string, size: 32, null: false
      add :resource_type, :string, size: 32, null: false
      add :resource_id, :binary_id
      add :metadata, :map, default: %{}
      add :ip_address, :string, size: 45
      add :user_agent, :string, size: 512

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:activity_logs, [:user_id, :inserted_at])
    create index(:activity_logs, [:resource_type, :resource_id])
  end
end
