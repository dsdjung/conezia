defmodule Conezia.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 50, null: false
      add :color, :string, size: 16, default: "blue"
      add :description, :string, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tags, [:user_id, :name])
    create index(:tags, [:user_id])
  end
end
