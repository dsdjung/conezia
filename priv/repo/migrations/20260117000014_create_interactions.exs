defmodule Conezia.Repo.Migrations.CreateInteractions do
  use Ecto.Migration

  def change do
    create table(:interactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32, null: false
      add :title, :string, size: 255
      add :content, :text, null: false
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:interactions, [:user_id])
    create index(:interactions, [:entity_id])
    create index(:interactions, [:occurred_at])
  end
end
