defmodule Conezia.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :title, :string, size: 255, null: false
      add :title_encrypted, :binary
      add :description, :text
      add :description_encrypted, :binary
      add :type, :string, size: 32, null: false

      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec
      add :all_day, :boolean, default: false, null: false

      add :location, :string, size: 500
      add :location_encrypted, :binary

      add :is_recurring, :boolean, default: false, null: false
      add :recurrence_rule, :map

      add :notes, :text
      add :notes_encrypted, :binary

      add :reminder_id, references(:reminders, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:events, [:user_id, :starts_at])
    create index(:events, [:user_id, :type])
    create index(:events, [:user_id, :is_recurring])
    create index(:events, [:reminder_id])

    create table(:event_entities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, size: 64

      timestamps(type: :utc_datetime_usec)
    end

    create index(:event_entities, [:event_id])
    create index(:event_entities, [:entity_id])
    create unique_index(:event_entities, [:event_id, :entity_id])
  end
end
