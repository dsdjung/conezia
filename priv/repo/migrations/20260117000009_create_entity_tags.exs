defmodule Conezia.Repo.Migrations.CreateEntityTags do
  use Ecto.Migration

  def change do
    create table(:entity_tags, primary_key: false) do
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:entity_tags, [:entity_id, :tag_id])
    create index(:entity_tags, [:tag_id])
  end
end
