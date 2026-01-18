defmodule Conezia.Repo.Migrations.CreateReminders do
  use Ecto.Migration

  def change do
    create table(:reminders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :set_null)
      add :type, :string, size: 32, null: false
      add :title, :string, size: 255, null: false
      add :description, :text
      add :due_at, :utc_datetime_usec, null: false
      add :recurrence_rule, :map
      add :notification_channels, {:array, :string}, default: ["in_app"]
      add :snoozed_until, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reminders, [:user_id, :completed_at])
    create index(:reminders, [:user_id, :due_at])
    create index(:reminders, [:entity_id])

    # Index for finding due reminders
    execute """
    CREATE INDEX reminders_due_pending_idx ON reminders (due_at)
    WHERE completed_at IS NULL AND (snoozed_until IS NULL OR snoozed_until < now());
    """, """
    DROP INDEX reminders_due_pending_idx;
    """
  end
end
