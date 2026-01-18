defmodule Conezia.Repo.Migrations.CreateApplications do
  use Ecto.Migration

  def change do
    create table(:applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :developer_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 100, null: false
      add :description, :text
      add :logo_url, :string, size: 2048
      add :website_url, :string, size: 2048
      add :callback_urls, {:array, :string}, default: []
      add :api_key_hash, :string, size: 64, null: false
      add :api_secret_hash, :string, size: 64, null: false
      add :scopes, {:array, :string}, default: []
      add :status, :string, size: 16, default: "pending"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:applications, [:developer_id])
    create unique_index(:applications, [:api_key_hash])
  end
end
