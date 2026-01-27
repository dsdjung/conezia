defmodule Conezia.Repo.Migrations.AddEncryptedColumns do
  use Ecto.Migration

  @moduledoc """
  Add encrypted columns across all schemas that store sensitive PII.
  Uses dual-field pattern: encrypted columns alongside existing plaintext
  for safe migration. Plaintext columns can be dropped in a future migration.
  """

  def change do
    # Entity: encrypt description
    alter table(:entities) do
      add :description_encrypted, :binary
    end

    # Custom fields: encrypt text values and number values
    alter table(:custom_fields) do
      add :value_encrypted, :binary
      add :number_value_encrypted, :binary
    end

    # Interactions: encrypt title and content
    alter table(:interactions) do
      add :title_encrypted, :binary
      add :content_encrypted, :binary
    end

    # Communications: encrypt subject and content
    alter table(:communications) do
      add :subject_encrypted, :binary
      add :content_encrypted, :binary
    end

    # Gifts: encrypt name, description, notes
    alter table(:gifts) do
      add :name_encrypted, :binary
      add :description_encrypted, :binary
      add :notes_encrypted, :binary
    end

    # Reminders: encrypt title and description
    alter table(:reminders) do
      add :title_encrypted, :binary
      add :description_encrypted, :binary
    end
  end
end
