defmodule Conezia.Communications.Conversation do
  @moduledoc """
  Conversation schema for grouping related communications.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channels ~w(internal email sms whatsapp telegram phone)

  schema "conversations" do
    field :channel, :string
    field :subject, :string
    field :last_message_at, :utc_datetime_usec
    field :is_archived, :boolean, default: false

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity
    has_many :communications, Conezia.Communications.Communication

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:channel, :user_id, :entity_id]
  @optional_fields [:subject, :last_message_at, :is_archived]

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:channel, @channels)
    |> validate_length(:subject, max: 255)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  def valid_channels, do: @channels
end
