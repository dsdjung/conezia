defmodule Conezia.Interactions.Interaction do
  @moduledoc """
  Interaction schema for recording communication history with connections.

  Interactions represent stored records of communication events - calls, meetings,
  emails, and messages. This forms the history timeline of interactions with a connection.

  Note: This is distinct from the UI concept of "Activity" which combines
  stored Interactions with on-demand data fetched from external APIs (Gmail, Calendar).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @interaction_types ~w(email call meeting message)

  schema "interactions" do
    field :type, :string
    field :title, :string
    field :content, :string
    field :occurred_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity
    has_many :attachments, Conezia.Attachments.Attachment

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :content, :user_id, :entity_id]
  @optional_fields [:title, :occurred_at]

  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @interaction_types)
    |> validate_length(:title, max: 255)
    |> validate_length(:content, min: 1, max: 50_000)
    |> set_default_occurred_at()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  defp set_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  def valid_types, do: @interaction_types
end
