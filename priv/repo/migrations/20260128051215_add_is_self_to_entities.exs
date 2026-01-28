defmodule Conezia.Repo.Migrations.AddIsSelfToEntities do
  use Ecto.Migration

  def change do
    alter table(:entities) do
      add :is_self, :boolean, default: false, null: false
    end

    # Ensure only one self entity per user
    create unique_index(:entities, [:owner_id], where: "is_self = true", name: :entities_one_self_per_owner)
  end
end
