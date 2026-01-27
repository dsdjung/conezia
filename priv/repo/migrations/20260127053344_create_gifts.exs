defmodule Conezia.Repo.Migrations.CreateGifts do
  use Ecto.Migration

  def change do
    create table(:gifts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :reminder_id, references(:reminders, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, size: 255, null: false
      add :description, :text
      add :status, :string, size: 32, null: false, default: "idea"
      add :occasion, :string, size: 32, null: false
      add :occasion_date, :date
      add :budget_cents, :integer
      add :actual_cost_cents, :integer
      add :url, :text
      add :notes, :text
      add :given_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:gifts, [:user_id, :status])
    create index(:gifts, [:user_id, :occasion_date])
    create index(:gifts, [:entity_id])
    create index(:gifts, [:reminder_id])
  end
end
