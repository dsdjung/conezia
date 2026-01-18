defmodule Conezia.Repo.Migrations.CreateWebhooks do
  use Ecto.Migration

  def change do
    create table(:webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all), null: false
      add :url, :string, size: 2048, null: false
      add :events, {:array, :string}, default: []
      add :secret, :string, size: 64, null: false
      add :status, :string, size: 16, default: "active"
      add :last_triggered_at, :utc_datetime_usec
      add :failure_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:webhooks, [:application_id, :status])
  end
end
