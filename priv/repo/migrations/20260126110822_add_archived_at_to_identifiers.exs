defmodule Conezia.Repo.Migrations.AddArchivedAtToIdentifiers do
  use Ecto.Migration

  def change do
    alter table(:identifiers) do
      add :archived_at, :utc_datetime_usec
    end

    create index(:identifiers, [:archived_at])
  end
end
