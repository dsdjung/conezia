defmodule Conezia.Events.Event do
  @moduledoc """
  Event schema for tracking one-time and recurring events linked to entities.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(birthday anniversary holiday celebration wedding memorial meeting dinner party reunion trip other)

  schema "events" do
    field :title, :string
    field :title_encrypted, Conezia.Encrypted.Binary
    field :description, :string
    field :description_encrypted, Conezia.Encrypted.Binary
    field :type, :string
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :all_day, :boolean, default: false
    field :location, :string
    field :location_encrypted, Conezia.Encrypted.Binary
    field :is_recurring, :boolean, default: false
    field :remind_yearly, :boolean, default: false
    field :recurrence_rule, :map
    field :notes, :string
    field :notes_encrypted, Conezia.Encrypted.Binary

    belongs_to :user, Conezia.Accounts.User
    belongs_to :reminder, Conezia.Reminders.Reminder

    many_to_many :entities, Conezia.Entities.Entity,
      join_through: "event_entities"

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:title, :type, :starts_at, :user_id]
  @optional_fields [
    :description, :ends_at, :all_day, :location, :is_recurring,
    :remind_yearly, :recurrence_rule, :notes, :reminder_id
  ]

  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @event_types)
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 5000)
    |> validate_length(:location, max: 500)
    |> validate_length(:notes, max: 10_000)
    |> validate_recurrence_rule()
    |> validate_end_time()
    |> encrypt_fields()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:reminder_id)
  end

  defp validate_recurrence_rule(changeset) do
    validate_change(changeset, :recurrence_rule, fn :recurrence_rule, rule ->
      case rule do
        nil -> []
        %{"freq" => freq} when freq in ~w(daily weekly monthly yearly) -> []
        _ -> [recurrence_rule: "must have a valid freq (daily, weekly, monthly, yearly)"]
      end
    end)
  end

  defp validate_end_time(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "must be after start time")
    else
      changeset
    end
  end

  defp encrypt_fields(changeset) do
    changeset
    |> maybe_encrypt(:title, :title_encrypted)
    |> maybe_encrypt(:description, :description_encrypted)
    |> maybe_encrypt(:location, :location_encrypted)
    |> maybe_encrypt(:notes, :notes_encrypted)
  end

  defp maybe_encrypt(changeset, field, encrypted_field) do
    case get_change(changeset, field) do
      nil -> changeset
      value -> put_change(changeset, encrypted_field, value)
    end
  end

  def valid_types, do: @event_types
end
