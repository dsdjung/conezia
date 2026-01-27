defmodule Conezia.Entities.Entity do
  @moduledoc """
  Entity schema representing people, organizations, and other relationship targets.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entity_types ~w(person organization service thing animal abstract)

  schema "entities" do
    field :type, :string
    field :name, :string
    field :description, :string
    field :avatar_url, :string
    field :metadata, :map, default: %{}
    field :last_interaction_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec

    # Demographic/profile fields
    field :country, :string
    field :timezone, :string
    field :nationality, :string
    field :ethnicity, :string
    field :languages, {:array, :string}, default: []
    field :preferred_language, :string

    belongs_to :owner, Conezia.Accounts.User
    has_many :relationships, Conezia.Entities.Relationship
    has_many :identifiers, Conezia.Entities.Identifier
    has_many :custom_fields, Conezia.Entities.CustomField
    has_many :interactions, Conezia.Interactions.Interaction
    has_many :conversations, Conezia.Communications.Conversation
    has_many :reminders, Conezia.Reminders.Reminder
    has_many :attachments, Conezia.Attachments.Attachment

    many_to_many :tags, Conezia.Entities.Tag, join_through: "entity_tags"
    many_to_many :groups, Conezia.Entities.Group, join_through: "entity_groups"

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :name, :owner_id]
  @optional_fields [
    :description, :avatar_url, :metadata, :last_interaction_at, :archived_at,
    :country, :timezone, :nationality, :ethnicity, :languages, :preferred_language
  ]

  def changeset(entity, attrs) do
    entity
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @entity_types)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 10_000)
    |> validate_length(:country, max: 2)
    |> validate_length(:nationality, max: 2)
    |> validate_length(:timezone, max: 64)
    |> validate_length(:ethnicity, max: 128)
    |> validate_length(:preferred_language, max: 8)
    |> validate_url(:avatar_url)
    |> foreign_key_constraint(:owner_id)
  end

  def archive_changeset(entity) do
    change(entity, archived_at: DateTime.utc_now())
  end

  def unarchive_changeset(entity) do
    change(entity, archived_at: nil)
  end

  def touch_interaction_changeset(entity) do
    change(entity, last_interaction_at: DateTime.utc_now())
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case value do
        nil -> []
        "" -> []
        url ->
          case URI.parse(url) do
            %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
              []
            _ ->
              [{field, "must be a valid URL"}]
          end
      end
    end)
  end

  def valid_types, do: @entity_types
end
