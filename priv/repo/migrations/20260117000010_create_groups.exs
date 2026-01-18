defmodule Conezia.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 100, null: false
      add :description, :string, size: 500
      add :is_smart, :boolean, default: false
      add :rules, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:groups, [:user_id, :name])
    create index(:groups, [:user_id])
  end
end
