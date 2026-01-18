defmodule Conezia.Entities.Relationship do
  @moduledoc """
  Relationship schema representing the connection between a user and an entity.

  ## Relationship Types and Subtypes

  The relationship type provides the broad category, while subtype provides specificity.

  | Type | Subtypes |
  |------|----------|
  | family | spouse, partner, parent, child, sibling, grandparent, grandchild, aunt_uncle, cousin, niece_nephew, in_law, step_family |
  | friend | close_friend, childhood_friend, school_friend, online_friend |
  | colleague | coworker, manager, direct_report, mentor, mentee, former_colleague |
  | professional | client, vendor, consultant, contractor, partner, investor |
  | community | neighbor, club_member, religious_community, volunteer |
  | service | doctor, lawyer, accountant, therapist, trainer, teacher |
  | other | (custom_label can be used) |
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Main relationship categories
  @relationship_types ~w(family friend colleague professional community service acquaintance other)

  # Subtypes by category
  @family_subtypes ~w(spouse partner parent child sibling grandparent grandchild aunt_uncle cousin niece_nephew in_law step_family)
  @friend_subtypes ~w(close_friend childhood_friend school_friend college_friend online_friend)
  @colleague_subtypes ~w(coworker manager direct_report mentor mentee former_colleague team_member)
  @professional_subtypes ~w(client vendor consultant contractor business_partner investor advisor)
  @community_subtypes ~w(neighbor club_member religious_community volunteer classmate alumni)
  @service_subtypes ~w(doctor dentist lawyer accountant therapist trainer coach teacher tutor caregiver)

  @all_subtypes @family_subtypes ++
                  @friend_subtypes ++
                  @colleague_subtypes ++
                  @professional_subtypes ++
                  @community_subtypes ++
                  @service_subtypes

  @strength_levels ~w(close regular acquaintance)
  @statuses ~w(active inactive archived)

  schema "relationships" do
    field :type, :string
    field :subtype, :string
    field :custom_label, :string  # User-defined label when subtype doesn't fit
    field :strength, :string, default: "regular"
    field :status, :string, default: "active"
    field :started_at, :date
    field :health_threshold_days, :integer, default: 30
    field :notes, :string

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :entity_id]
  @optional_fields [:type, :subtype, :custom_label, :strength, :status, :started_at, :health_threshold_days, :notes]

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @relationship_types)
    |> validate_subtype()
    |> validate_inclusion(:strength, @strength_levels)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:health_threshold_days, greater_than: 0, less_than_or_equal_to: 365)
    |> validate_length(:notes, max: 5000)
    |> validate_length(:custom_label, max: 100)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
    |> unique_constraint([:user_id, :entity_id])
  end

  # Validate subtype if provided
  defp validate_subtype(changeset) do
    case get_field(changeset, :subtype) do
      nil -> changeset
      subtype ->
        type = get_field(changeset, :type)
        valid_subtypes = subtypes_for_type(type)

        if subtype in valid_subtypes do
          changeset
        else
          add_error(changeset, :subtype, "is not valid for relationship type '#{type}'")
        end
    end
  end

  @doc """
  Returns valid subtypes for a given relationship type.
  """
  def subtypes_for_type("family"), do: @family_subtypes
  def subtypes_for_type("friend"), do: @friend_subtypes
  def subtypes_for_type("colleague"), do: @colleague_subtypes
  def subtypes_for_type("professional"), do: @professional_subtypes
  def subtypes_for_type("community"), do: @community_subtypes
  def subtypes_for_type("service"), do: @service_subtypes
  def subtypes_for_type(_), do: []

  @doc """
  Returns a human-readable label for the relationship.
  Prioritizes custom_label, then subtype, then type.
  """
  def display_label(%__MODULE__{custom_label: label}) when is_binary(label) and label != "", do: humanize(label)
  def display_label(%__MODULE__{subtype: subtype}) when is_binary(subtype), do: humanize(subtype)
  def display_label(%__MODULE__{type: type}) when is_binary(type), do: humanize(type)
  def display_label(_), do: "Connection"

  defp humanize(str) do
    str
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  def valid_types, do: @relationship_types
  def valid_subtypes, do: @all_subtypes
  def valid_strengths, do: @strength_levels
  def valid_statuses, do: @statuses

  @doc """
  Returns all types with their subtypes for UI display.
  """
  def types_with_subtypes do
    [
      %{type: "family", label: "Family", subtypes: format_subtypes(@family_subtypes)},
      %{type: "friend", label: "Friend", subtypes: format_subtypes(@friend_subtypes)},
      %{type: "colleague", label: "Colleague", subtypes: format_subtypes(@colleague_subtypes)},
      %{type: "professional", label: "Professional", subtypes: format_subtypes(@professional_subtypes)},
      %{type: "community", label: "Community", subtypes: format_subtypes(@community_subtypes)},
      %{type: "service", label: "Service Provider", subtypes: format_subtypes(@service_subtypes)},
      %{type: "acquaintance", label: "Acquaintance", subtypes: []},
      %{type: "other", label: "Other", subtypes: []}
    ]
  end

  defp format_subtypes(subtypes) do
    Enum.map(subtypes, fn subtype ->
      %{value: subtype, label: humanize(subtype)}
    end)
  end
end
