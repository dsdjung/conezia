defmodule Conezia.Attachments.Attachment do
  @moduledoc """
  Attachment schema for files associated with entities, interactions, or communications.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_file_size 50 * 1024 * 1024  # 50 MB
  @allowed_mime_types ~w(
    image/jpeg image/png image/gif image/webp
    application/pdf
    text/plain text/csv
    application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  )

  schema "attachments" do
    field :filename, :string
    field :mime_type, :string
    field :size_bytes, :integer
    field :storage_key, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity
    belongs_to :interaction, Conezia.Interactions.Interaction
    belongs_to :communication, Conezia.Communications.Communication

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:filename, :mime_type, :size_bytes, :storage_key, :user_id]
  @optional_fields [:entity_id, :interaction_id, :communication_id, :deleted_at]

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_inclusion(:mime_type, @allowed_mime_types)
    |> validate_number(:size_bytes, greater_than: 0, less_than_or_equal_to: @max_file_size)
    |> validate_at_least_one_parent()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
    |> foreign_key_constraint(:interaction_id)
    |> foreign_key_constraint(:communication_id)
  end

  defp validate_at_least_one_parent(changeset) do
    entity_id = get_field(changeset, :entity_id)
    interaction_id = get_field(changeset, :interaction_id)
    communication_id = get_field(changeset, :communication_id)

    if entity_id || interaction_id || communication_id do
      changeset
    else
      add_error(changeset, :entity_id, "at least one of entity_id, interaction_id, or communication_id is required")
    end
  end

  def max_file_size, do: @max_file_size
  def allowed_mime_types, do: @allowed_mime_types
end
