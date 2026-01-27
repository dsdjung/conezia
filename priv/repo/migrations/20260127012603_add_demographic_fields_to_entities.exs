defmodule Conezia.Repo.Migrations.AddDemographicFieldsToEntities do
  use Ecto.Migration

  def change do
    alter table(:entities) do
      # Location/Geographic
      add :country, :string, size: 2  # ISO 3166-1 alpha-2 country code
      add :timezone, :string, size: 64  # IANA timezone (e.g., "America/New_York")

      # Cultural/Background
      add :nationality, :string, size: 2  # ISO 3166-1 alpha-2 country code
      add :ethnicity, :string, size: 128

      # Languages (stored as array of language codes)
      add :languages, {:array, :string}, default: []

      # Communication preferences
      add :preferred_language, :string, size: 8  # BCP 47 language tag (e.g., "en", "es", "zh-Hans")
    end

    # Index for filtering by country
    create index(:entities, [:country])
  end
end
