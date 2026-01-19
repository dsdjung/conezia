defmodule Conezia.Entities.EntityRelationship do
  @moduledoc """
  Schema for relationships between entities (connection-to-connection relationships).

  This allows modeling relationships like:
  - "John is Mary's brother"
  - "Alice and Bob are friends"
  - "Company X employs Person Y"

  ## Bidirectional vs Directional Relationships

  - **Bidirectional (symmetric)**: Both entities have the same relationship to each other.
    Example: "friends", "colleagues", "neighbors"

  - **Directional (asymmetric)**: Each entity has a different relationship to the other.
    Example: "parent/child", "employer/employee", "mentor/mentee"

  For directional relationships, we store both the forward relationship (source -> target)
  and the inverse relationship (target -> source) in the same record.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Conezia.Entities.Relationship

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Symmetric relationship types (both directions are the same)
  @symmetric_types ~w(friend colleague neighbor classmate)

  # Asymmetric relationship pairs (forward -> inverse)
  @asymmetric_pairs %{
    # Family
    "parent" => "child",
    "child" => "parent",
    "grandparent" => "grandchild",
    "grandchild" => "grandparent",
    "aunt_uncle" => "niece_nephew",
    "niece_nephew" => "aunt_uncle",
    "older_sibling" => "younger_sibling",
    "younger_sibling" => "older_sibling",
    # Professional
    "employer" => "employee",
    "employee" => "employer",
    "manager" => "direct_report",
    "direct_report" => "manager",
    "mentor" => "mentee",
    "mentee" => "mentor",
    "client" => "service_provider",
    "service_provider" => "client"
  }

  schema "entity_relationships" do
    field :type, :string
    field :subtype, :string
    field :custom_label, :string
    field :notes, :string
    field :is_bidirectional, :boolean, default: true

    # For directional relationships
    field :inverse_type, :string
    field :inverse_subtype, :string
    field :inverse_custom_label, :string

    belongs_to :user, Conezia.Accounts.User
    belongs_to :source_entity, Conezia.Entities.Entity
    belongs_to :target_entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :source_entity_id, :target_entity_id]
  @optional_fields [:type, :subtype, :custom_label, :notes, :is_bidirectional,
                    :inverse_type, :inverse_subtype, :inverse_custom_label]

  def changeset(entity_relationship, attrs) do
    entity_relationship
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_different_entities()
    |> validate_type_if_present()
    |> validate_inverse_type_if_present()
    |> validate_length(:custom_label, max: 100)
    |> validate_length(:inverse_custom_label, max: 100)
    |> validate_length(:notes, max: 5000)
    |> maybe_set_inverse_from_subtype()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:source_entity_id)
    |> foreign_key_constraint(:target_entity_id)
    |> unique_constraint([:user_id, :source_entity_id, :target_entity_id],
      name: "entity_relationships_user_id_source_entity_id_target_entity_id_"
    )
  end

  defp validate_type_if_present(changeset) do
    case get_field(changeset, :type) do
      nil -> changeset
      _type -> validate_inclusion(changeset, :type, Relationship.valid_types())
    end
  end

  defp validate_inverse_type_if_present(changeset) do
    case get_field(changeset, :inverse_type) do
      nil -> changeset
      _type -> validate_inclusion(changeset, :inverse_type, Relationship.valid_types())
    end
  end

  defp validate_different_entities(changeset) do
    source_id = get_field(changeset, :source_entity_id)
    target_id = get_field(changeset, :target_entity_id)

    if source_id && target_id && source_id == target_id do
      add_error(changeset, :target_entity_id, "cannot be the same as source entity")
    else
      changeset
    end
  end

  # Auto-set inverse relationship for known asymmetric subtypes
  defp maybe_set_inverse_from_subtype(changeset) do
    subtype = get_field(changeset, :subtype)

    cond do
      is_nil(subtype) -> changeset
      subtype in @symmetric_types ->
        changeset
        |> put_change(:is_bidirectional, true)
      inverse = Map.get(@asymmetric_pairs, subtype) ->
        changeset
        |> put_change(:is_bidirectional, false)
        |> put_change(:inverse_subtype, inverse)
        |> maybe_set_inverse_type()
      true -> changeset
    end
  end

  defp maybe_set_inverse_type(changeset) do
    type = get_field(changeset, :type)
    inverse_type = get_field(changeset, :inverse_type)

    if is_nil(inverse_type) && type do
      put_change(changeset, :inverse_type, type)
    else
      changeset
    end
  end

  @doc """
  Returns the display label for this relationship from the perspective of the source entity.
  """
  def display_label_for_source(%__MODULE__{} = rel) do
    cond do
      rel.custom_label && rel.custom_label != "" -> humanize(rel.custom_label)
      rel.subtype -> humanize(rel.subtype)
      rel.type -> humanize(rel.type)
      true -> "Connected to"
    end
  end

  @doc """
  Returns the display label for this relationship from the perspective of the target entity.
  """
  def display_label_for_target(%__MODULE__{} = rel) do
    if rel.is_bidirectional do
      display_label_for_source(rel)
    else
      cond do
        rel.inverse_custom_label && rel.inverse_custom_label != "" -> humanize(rel.inverse_custom_label)
        rel.inverse_subtype -> humanize(rel.inverse_subtype)
        rel.inverse_type -> humanize(rel.inverse_type)
        true -> "Connected to"
      end
    end
  end

  @doc """
  Returns the display label from the perspective of a given entity.
  """
  def display_label_for(%__MODULE__{source_entity_id: source_id} = rel, entity_id) do
    if entity_id == source_id do
      display_label_for_source(rel)
    else
      display_label_for_target(rel)
    end
  end

  @doc """
  Returns the "other" entity in the relationship given one entity's ID.
  """
  def other_entity_id(%__MODULE__{source_entity_id: source_id, target_entity_id: target_id}, entity_id) do
    if entity_id == source_id, do: target_id, else: source_id
  end

  defp humanize(str) when is_binary(str) do
    str
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Returns symmetric relationship types.
  """
  def symmetric_types, do: @symmetric_types

  @doc """
  Returns asymmetric relationship pairs.
  """
  def asymmetric_pairs, do: @asymmetric_pairs

  @doc """
  Returns the inverse subtype for an asymmetric relationship.
  """
  def inverse_of(subtype), do: Map.get(@asymmetric_pairs, subtype)
end
