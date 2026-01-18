defmodule Conezia.Repo.Migrations.LinkImportJobsToExternalAccounts do
  use Ecto.Migration

  def change do
    alter table(:import_jobs) do
      add :external_account_id, references(:external_accounts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:import_jobs, [:external_account_id])
  end
end
