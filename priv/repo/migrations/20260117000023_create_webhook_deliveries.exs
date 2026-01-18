defmodule Conezia.Repo.Migrations.CreateWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :webhook_id, references(:webhooks, type: :binary_id, on_delete: :delete_all), null: false
      add :event_type, :string, size: 64, null: false
      add :payload, :map, null: false
      add :response_status, :integer
      add :response_body, :text
      add :delivered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:webhook_deliveries, [:webhook_id, :inserted_at])
  end
end
