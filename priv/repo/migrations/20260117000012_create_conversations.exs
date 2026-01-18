defmodule Conezia.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :string, size: 32, null: false
      add :subject, :string, size: 255
      add :last_message_at, :utc_datetime_usec
      add :is_archived, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversations, [:user_id, :is_archived])
    create index(:conversations, [:entity_id])
    create index(:conversations, [:last_message_at])
  end
end
