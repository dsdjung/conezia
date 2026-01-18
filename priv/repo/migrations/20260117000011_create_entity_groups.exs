defmodule Conezia.Repo.Migrations.CreateEntityGroups do
  use Ecto.Migration

  def change do
    create table(:entity_groups, primary_key: false) do
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :added_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:entity_groups, [:entity_id, :group_id])
    create index(:entity_groups, [:group_id])
  end
end
