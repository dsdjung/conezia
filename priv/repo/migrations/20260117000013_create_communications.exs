defmodule Conezia.Repo.Migrations.CreateCommunications do
  use Ecto.Migration

  def change do
    create table(:communications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :string, size: 32, null: false
      add :direction, :string, size: 16, null: false
      add :content, :text, null: false
      add :attachments, {:array, :map}, default: []
      add :sent_at, :utc_datetime_usec
      add :read_at, :utc_datetime_usec
      add :external_id, :string, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create index(:communications, [:conversation_id])
    create index(:communications, [:user_id, :entity_id])
    create index(:communications, [:sent_at])
    create index(:communications, [:external_id])
  end
end
