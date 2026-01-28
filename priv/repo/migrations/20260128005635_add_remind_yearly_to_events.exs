defmodule Conezia.Repo.Migrations.AddRemindYearlyToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :remind_yearly, :boolean, default: false, null: false
    end
  end
end
