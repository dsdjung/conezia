defmodule Conezia.Repo.Migrations.AddEntityRelationships do
  use Ecto.Migration

  def change do
    create table(:entity_relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # The two entities in the relationship
      add :source_entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :target_entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false

      # Relationship details (same types as user-entity relationships)
      add :type, :string
      add :subtype, :string
      add :custom_label, :string
      add :notes, :text

      # Bidirectional relationship support
      # If true, the relationship is symmetric (A is friend of B means B is friend of A)
      # If false, relationship is directional (A is parent of B, but B is child of A)
      add :is_bidirectional, :boolean, default: true

      # For directional relationships, store the inverse type/subtype
      add :inverse_type, :string
      add :inverse_subtype, :string
      add :inverse_custom_label, :string

      timestamps(type: :utc_datetime_usec)
    end

    # Ensure a relationship between two entities is unique for a user
    # Note: we don't use a simple unique constraint because A->B and B->A should be considered the same
    create index(:entity_relationships, [:user_id, :source_entity_id, :target_entity_id], unique: true)
    create index(:entity_relationships, [:user_id, :target_entity_id, :source_entity_id])
    create index(:entity_relationships, [:source_entity_id])
    create index(:entity_relationships, [:target_entity_id])
    create index(:entity_relationships, [:type])
  end
end
