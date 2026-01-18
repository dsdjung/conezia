defmodule Conezia.Repo.Migrations.CreateAuthProviders do
  use Ecto.Migration

  def change do
    create table(:auth_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, size: 32, null: false
      add :provider_uid, :string, size: 255, null: false
      add :provider_token, :binary
      add :provider_refresh_token, :binary
      add :provider_meta, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:auth_providers, [:provider, :provider_uid])
    create index(:auth_providers, [:user_id])
  end
end
