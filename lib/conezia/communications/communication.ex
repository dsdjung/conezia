defmodule Conezia.Communications.Communication do
  @moduledoc """
  Communication schema for individual messages within a conversation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channels ~w(internal email sms whatsapp telegram phone)
  @directions ~w(inbound outbound)

  schema "communications" do
    field :channel, :string
    field :direction, :string
    field :content, :string
    field :attachments, {:array, :map}, default: []
    field :sent_at, :utc_datetime_usec
    field :read_at, :utc_datetime_usec
    field :external_id, :string

    belongs_to :conversation, Conezia.Communications.Conversation
    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:channel, :direction, :content, :user_id, :entity_id]
  @optional_fields [:conversation_id, :attachments, :sent_at, :read_at, :external_id]

  def changeset(communication, attrs) do
    communication
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:direction, @directions)
    |> validate_length(:content, min: 1, max: 100_000)
    |> validate_attachments()
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  defp validate_attachments(changeset) do
    validate_change(changeset, :attachments, fn :attachments, attachments ->
      Enum.flat_map(attachments, fn attachment ->
        case attachment do
          %{"id" => _, "filename" => _, "mime_type" => _} -> []
          _ -> [attachments: "each attachment must have id, filename, and mime_type"]
        end
      end)
    end)
  end

  def valid_channels, do: @channels
  def valid_directions, do: @directions
end
