defmodule Conezia.Repo.Migrations.CreateApplicationUsers do
  use Ecto.Migration

  def change do
    create table(:application_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :external_user_id, :string, size: 255
      add :granted_scopes, {:array, :string}, default: []
      add :authorized_at, :utc_datetime_usec
      add :last_accessed_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:application_users, [:application_id, :user_id])
    create index(:application_users, [:user_id])
    create index(:application_users, [:application_id, :authorized_at])
  end
end
