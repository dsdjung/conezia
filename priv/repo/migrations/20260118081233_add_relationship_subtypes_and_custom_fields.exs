defmodule Conezia.Repo.Migrations.AddRelationshipSubtypesAndCustomFields do
  use Ecto.Migration

  def change do
    # Add subtype to relationships for more granular categorization
    alter table(:relationships) do
      add :subtype, :string
      add :custom_label, :string  # For user-defined relationship labels
    end

    # Create custom_fields table for flexible entity data storage
    # This allows users to store important dates, preferences, and other custom data
    create table(:custom_fields, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :field_type, :string, null: false  # date, text, number, boolean, url, email, phone
      add :category, :string  # important_dates, preferences, social, work, personal
      add :name, :string, null: false  # field display name (e.g., "Birthday", "Favorite Color")
      add :key, :string, null: false  # normalized key (e.g., "birthday", "favorite_color")
      add :value, :text  # string value
      add :date_value, :date  # for date fields
      add :number_value, :decimal  # for numeric fields
      add :boolean_value, :boolean  # for boolean fields
      add :is_recurring, :boolean, default: false  # for dates like birthdays, anniversaries
      add :reminder_days_before, :integer  # auto-create reminder X days before date
      add :visibility, :string, default: "private"  # private, shared

      timestamps(type: :utc_datetime_usec)
    end

    create index(:custom_fields, [:entity_id])
    create index(:custom_fields, [:entity_id, :category])
    create index(:custom_fields, [:entity_id, :field_type])
    create unique_index(:custom_fields, [:entity_id, :key])

    # Index for finding entities with upcoming dates
    create index(:custom_fields, [:date_value])
    create index(:custom_fields, [:field_type, :date_value], where: "field_type = 'date'")

    # Add index for relationship subtypes
    create index(:relationships, [:type, :subtype])
  end
end
