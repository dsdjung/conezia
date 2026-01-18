defmodule Conezia.Repo.Migrations.CreateAttachments do
  use Ecto.Migration

  def change do
    create table(:attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :nilify_all)
      add :interaction_id, references(:interactions, type: :binary_id, on_delete: :nilify_all)
      add :communication_id, references(:communications, type: :binary_id, on_delete: :nilify_all)
      add :filename, :string, size: 255, null: false
      add :mime_type, :string, size: 128, null: false
      add :size_bytes, :bigint, null: false
      add :storage_key, :string, size: 512, null: false
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:attachments, [:user_id])
    create index(:attachments, [:entity_id])
    create index(:attachments, [:interaction_id])
    create index(:attachments, [:communication_id])
  end
end
