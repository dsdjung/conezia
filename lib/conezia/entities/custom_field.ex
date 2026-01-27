defmodule Conezia.Entities.CustomField do
  @moduledoc """
  Custom field schema for storing flexible entity data.

  Custom fields allow users to store additional information about entities
  such as important dates (birthdays, anniversaries), preferences, and other
  custom data that doesn't fit into the standard entity schema.

  ## Field Types

  | Type | Description | Storage Field |
  |------|-------------|---------------|
  | date | Date values (birthdays, anniversaries) | date_value |
  | text | Free-form text | value |
  | number | Numeric values | number_value |
  | boolean | Yes/no values | boolean_value |
  | url | Web links | value |
  | email | Email addresses | value |
  | phone | Phone numbers | value |

  ## Categories

  Fields can be organized into categories for grouping:
  - important_dates: Birthdays, anniversaries, etc.
  - preferences: Favorite things, dietary restrictions, etc.
  - social: Social media profiles
  - work: Professional information
  - personal: Personal details
  - medical: Health-related information
  - financial: Financial preferences
  - other: Miscellaneous

  ## Recurring Dates

  Date fields can be marked as recurring (is_recurring: true) for annual events
  like birthdays. These can optionally have reminder_days_before set to automatically
  create reminders.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @field_types ~w(date text number boolean url email phone)
  @categories ~w(important_dates preferences social work personal medical financial other)
  @visibilities ~w(private shared)

  # Common predefined fields for quick access
  @predefined_fields [
    %{key: "birthday", name: "Birthday", field_type: "date", category: "important_dates", is_recurring: true},
    %{key: "anniversary", name: "Anniversary", field_type: "date", category: "important_dates", is_recurring: true},
    %{key: "first_met", name: "First Met", field_type: "date", category: "important_dates", is_recurring: false},
    %{key: "company", name: "Company", field_type: "text", category: "work"},
    %{key: "job_title", name: "Job Title", field_type: "text", category: "work"},
    %{key: "department", name: "Department", field_type: "text", category: "work"},
    %{key: "linkedin", name: "LinkedIn", field_type: "url", category: "social"},
    %{key: "twitter", name: "Twitter/X", field_type: "url", category: "social"},
    %{key: "instagram", name: "Instagram", field_type: "url", category: "social"},
    %{key: "facebook", name: "Facebook", field_type: "url", category: "social"},
    %{key: "dietary_restrictions", name: "Dietary Restrictions", field_type: "text", category: "preferences"},
    %{key: "favorite_food", name: "Favorite Food", field_type: "text", category: "preferences"},
    %{key: "favorite_drink", name: "Favorite Drink", field_type: "text", category: "preferences"},
    %{key: "hobbies", name: "Hobbies", field_type: "text", category: "preferences"},
    %{key: "allergies", name: "Allergies", field_type: "text", category: "medical"},
    %{key: "home_address", name: "Home Address", field_type: "text", category: "personal"},
    %{key: "work_address", name: "Work Address", field_type: "text", category: "work"},
    %{key: "nickname", name: "Nickname", field_type: "text", category: "personal"},
    %{key: "pronouns", name: "Pronouns", field_type: "text", category: "personal"},
    %{key: "timezone", name: "Timezone", field_type: "text", category: "personal"}
  ]

  schema "custom_fields" do
    field :field_type, :string
    field :category, :string
    field :name, :string
    field :key, :string
    field :value, :string
    field :value_encrypted, Conezia.Encrypted.Binary
    field :date_value, :date
    field :number_value, :decimal
    field :number_value_encrypted, Conezia.Encrypted.Binary
    field :boolean_value, :boolean
    field :is_recurring, :boolean, default: false
    field :reminder_days_before, :integer
    field :visibility, :string, default: "private"

    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:entity_id, :field_type, :name, :key]
  @optional_fields [:category, :value, :date_value, :number_value, :boolean_value,
                    :is_recurring, :reminder_days_before, :visibility]

  def changeset(custom_field, attrs) do
    custom_field
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:field_type, @field_types)
    |> validate_inclusion(:category, @categories ++ [nil])
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:key, min: 1, max: 100)
    |> validate_length(:value, max: 10_000)
    |> validate_number(:reminder_days_before, greater_than: 0, less_than_or_equal_to: 365)
    |> normalize_key()
    |> validate_value_for_type()
    |> encrypt_values()
    |> foreign_key_constraint(:entity_id)
    |> unique_constraint([:entity_id, :key])
  end

  # Normalize key to lowercase with underscores
  defp normalize_key(changeset) do
    case get_change(changeset, :key) do
      nil -> changeset
      key ->
        normalized = key
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "_")
        |> String.trim("_")

        put_change(changeset, :key, normalized)
    end
  end

  # Validate that the appropriate value field is set based on field_type
  defp validate_value_for_type(changeset) do
    field_type = get_field(changeset, :field_type)

    case field_type do
      "date" ->
        if get_field(changeset, :date_value) == nil do
          add_error(changeset, :date_value, "is required for date fields")
        else
          changeset
        end

      "number" ->
        if get_field(changeset, :number_value) == nil do
          add_error(changeset, :number_value, "is required for number fields")
        else
          changeset
        end

      "boolean" ->
        # Boolean can be nil (unset), so we don't require it
        changeset

      "url" ->
        validate_url(changeset)

      "email" ->
        validate_email(changeset)

      _ ->
        # text, phone just use value field, no special validation
        changeset
    end
  end

  defp validate_url(changeset) do
    case get_field(changeset, :value) do
      nil -> changeset
      "" -> changeset
      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
            changeset
          _ ->
            add_error(changeset, :value, "must be a valid URL")
        end
    end
  end

  defp validate_email(changeset) do
    case get_field(changeset, :value) do
      nil -> changeset
      "" -> changeset
      email ->
        if email =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/ do
          changeset
        else
          add_error(changeset, :value, "must be a valid email address")
        end
    end
  end

  defp encrypt_values(changeset) do
    changeset
    |> encrypt_text_value()
    |> encrypt_number_value()
  end

  defp encrypt_text_value(changeset) do
    case get_change(changeset, :value) do
      nil -> changeset
      value -> put_change(changeset, :value_encrypted, value)
    end
  end

  defp encrypt_number_value(changeset) do
    case get_change(changeset, :number_value) do
      nil -> changeset
      number -> put_change(changeset, :number_value_encrypted, Decimal.to_string(number))
    end
  end

  @doc """
  Returns the actual value based on field_type.
  Prefers encrypted fields, falls back to plaintext.
  """
  def get_value(%__MODULE__{field_type: "date", date_value: value}), do: value
  def get_value(%__MODULE__{field_type: "number", number_value_encrypted: enc}) when not is_nil(enc) do
    Decimal.new(enc)
  end
  def get_value(%__MODULE__{field_type: "number", number_value: value}), do: value
  def get_value(%__MODULE__{field_type: "boolean", boolean_value: value}), do: value
  def get_value(%__MODULE__{value_encrypted: enc}) when not is_nil(enc), do: enc
  def get_value(%__MODULE__{value: value}), do: value

  @doc """
  Sets the appropriate value field based on field_type.
  """
  def set_value(attrs, field_type, value) do
    case field_type do
      "date" -> Map.put(attrs, "date_value", value)
      "number" -> Map.put(attrs, "number_value", value)
      "boolean" -> Map.put(attrs, "boolean_value", value)
      _ -> Map.put(attrs, "value", value)
    end
  end

  def valid_field_types, do: @field_types
  def valid_categories, do: @categories
  def valid_visibilities, do: @visibilities
  def predefined_fields, do: @predefined_fields

  @doc """
  Returns predefined fields for a given category.
  """
  def predefined_fields_for_category(category) do
    Enum.filter(@predefined_fields, fn field -> field.category == category end)
  end

  @doc """
  Returns categories with their predefined fields for UI display.
  """
  def categories_with_fields do
    @categories
    |> Enum.map(fn category ->
      %{
        category: category,
        label: humanize_category(category),
        fields: predefined_fields_for_category(category)
      }
    end)
  end

  defp humanize_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
