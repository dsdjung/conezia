defmodule Conezia.Repo.Migrations.AddTokenExpiryToExternalAccounts do
  use Ecto.Migration

  def change do
    alter table(:external_accounts) do
      add :token_expires_at, :utc_datetime_usec
      add :last_token_refresh_at, :utc_datetime_usec
    end
  end
end
