defmodule Conezia.Repo.Migrations.CreateExternalAccounts do
  use Ecto.Migration

  def change do
    create table(:external_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :set_null)
      add :service_name, :string, size: 32, null: false
      add :account_identifier, :string, size: 255, null: false
      add :credentials, :binary  # Encrypted OAuth access token
      add :refresh_token, :binary  # Encrypted OAuth refresh token
      add :status, :string, size: 16, default: "connected"
      add :scopes, {:array, :string}, default: []
      add :last_synced_at, :utc_datetime_usec
      add :sync_error, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:external_accounts, [:user_id, :service_name, :account_identifier])
    create index(:external_accounts, [:user_id, :status])
    create index(:external_accounts, [:service_name])
  end
end
