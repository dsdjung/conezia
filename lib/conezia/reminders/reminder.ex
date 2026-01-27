defmodule Conezia.Reminders.Reminder do
  @moduledoc """
  Reminder schema for follow-ups, birthdays, and other time-based notifications.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reminder_types ~w(follow_up birthday anniversary custom health_alert event gift)
  @notification_channels ~w(in_app email push)

  schema "reminders" do
    field :type, :string
    field :title, :string
    field :title_encrypted, Conezia.Encrypted.Binary
    field :description, :string
    field :description_encrypted, Conezia.Encrypted.Binary
    field :due_at, :utc_datetime_usec
    field :recurrence_rule, :map
    field :notification_channels, {:array, :string}, default: ["in_app"]
    field :snoozed_until, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :title, :due_at, :user_id]
  @optional_fields [:description, :recurrence_rule, :notification_channels, :snoozed_until, :completed_at, :entity_id]

  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @reminder_types)
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> validate_notification_channels()
    |> validate_recurrence_rule()
    |> encrypt_fields()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  defp encrypt_fields(changeset) do
    changeset
    |> maybe_encrypt(:title, :title_encrypted)
    |> maybe_encrypt(:description, :description_encrypted)
  end

  defp maybe_encrypt(changeset, field, encrypted_field) do
    case get_change(changeset, field) do
      nil -> changeset
      value -> put_change(changeset, encrypted_field, value)
    end
  end

  def snooze_changeset(reminder, until) do
    change(reminder, snoozed_until: until)
    |> validate_snooze_time()
  end

  def complete_changeset(reminder) do
    change(reminder, completed_at: DateTime.utc_now())
  end

  defp validate_notification_channels(changeset) do
    validate_change(changeset, :notification_channels, fn :notification_channels, channels ->
      invalid = channels -- @notification_channels
      if invalid == [] do
        []
      else
        [notification_channels: "contains invalid channels: #{inspect(invalid)}"]
      end
    end)
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

  defp validate_snooze_time(changeset) do
    until = get_change(changeset, :snoozed_until)
    if until && DateTime.compare(until, DateTime.utc_now()) == :gt do
      changeset
    else
      add_error(changeset, :snoozed_until, "must be in the future")
    end
  end

  def valid_types, do: @reminder_types
  def valid_notification_channels, do: @notification_channels
end
