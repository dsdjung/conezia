defmodule Conezia.Repo.Migrations.CreateImportJobs do
  use Ecto.Migration

  def change do
    create table(:import_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :source, :string, size: 32, null: false
      add :status, :string, size: 16, default: "pending"
      add :total_records, :integer, default: 0
      add :processed_records, :integer, default: 0
      add :created_records, :integer, default: 0
      add :merged_records, :integer, default: 0
      add :skipped_records, :integer, default: 0
      add :error_log, {:array, :map}, default: []
      add :file_path, :string, size: 512
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:import_jobs, [:user_id, :status])
  end
end
