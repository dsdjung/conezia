defmodule Conezia.Validators.ReminderValidator do
  @moduledoc """
  Validation rules for reminder data.
  """
  import Ecto.Changeset

  @reminder_types ~w(follow_up birthday anniversary custom health_alert event)
  @notification_channels ~w(in_app email push)
  @recurrence_frequencies ~w(daily weekly monthly yearly)

  def validate_type(changeset) do
    changeset
    |> validate_required([:type])
    |> validate_inclusion(:type, @reminder_types,
        message: "must be one of: #{Enum.join(@reminder_types, ", ")}")
  end

  def validate_title(changeset) do
    changeset
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_not_blank(:title)
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 2000)
  end

  def validate_due_at(changeset, opts \\ []) do
    allow_past = Keyword.get(opts, :allow_past, false)

    changeset
    |> validate_required([:due_at])
    |> validate_due_at_constraints(allow_past)
  end

  defp validate_due_at_constraints(changeset, allow_past) do
    validate_change(changeset, :due_at, fn :due_at, due_at ->
      now = DateTime.utc_now()
      max_future = DateTime.add(now, 365 * 5 * 24 * 3600, :second)  # 5 years

      cond do
        !allow_past && DateTime.compare(due_at, now) != :gt ->
          [due_at: "must be in the future"]
        DateTime.compare(due_at, max_future) == :gt ->
          [due_at: "cannot be more than 5 years in the future"]
        true ->
          []
      end
    end)
  end

  def validate_notification_channels(changeset) do
    validate_change(changeset, :notification_channels, fn :notification_channels, channels ->
      cond do
        !is_list(channels) ->
          [notification_channels: "must be a list"]
        channels == [] ->
          [notification_channels: "must have at least one channel"]
        (invalid = channels -- @notification_channels) != [] ->
          [notification_channels: "contains invalid channels: #{inspect(invalid)}"]
        true ->
          []
      end
    end)
  end

  def validate_recurrence_rule(changeset) do
    validate_change(changeset, :recurrence_rule, fn :recurrence_rule, rule ->
      case rule do
        nil -> []
        %{} -> validate_recurrence_rule_structure(rule)
        _ -> [recurrence_rule: "must be a valid recurrence rule object"]
      end
    end)
  end

  defp validate_recurrence_rule_structure(rule) do
    errors = []

    # Validate freq (required for recurrence)
    errors = case Map.get(rule, "freq") do
      nil -> [{:recurrence_rule, "must have a 'freq' field"} | errors]
      freq when freq in @recurrence_frequencies -> errors
      _ -> [{:recurrence_rule, "freq must be one of: #{Enum.join(@recurrence_frequencies, ", ")}"} | errors]
    end

    # Validate interval if present
    errors = case Map.get(rule, "interval") do
      nil -> errors
      interval when is_integer(interval) and interval > 0 and interval <= 365 -> errors
      _ -> [{:recurrence_rule, "interval must be a positive integer up to 365"} | errors]
    end

    # Validate count if present
    errors = case Map.get(rule, "count") do
      nil -> errors
      count when is_integer(count) and count > 0 and count <= 1000 -> errors
      _ -> [{:recurrence_rule, "count must be a positive integer up to 1000"} | errors]
    end

    # Validate until if present
    errors = case Map.get(rule, "until") do
      nil -> errors
      until_str ->
        case DateTime.from_iso8601(until_str) do
          {:ok, _, _} -> errors
          _ -> [{:recurrence_rule, "until must be a valid ISO8601 datetime"} | errors]
        end
    end

    errors
  end

  def validate_snooze(changeset) do
    validate_change(changeset, :snoozed_until, fn :snoozed_until, snoozed_until ->
      now = DateTime.utc_now()
      max_snooze = DateTime.add(now, 30 * 24 * 3600, :second)  # 30 days

      cond do
        DateTime.compare(snoozed_until, now) != :gt ->
          [snoozed_until: "must be in the future"]
        DateTime.compare(snoozed_until, max_snooze) == :gt ->
          [snoozed_until: "cannot snooze more than 30 days"]
        true ->
          []
      end
    end)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end

  def reminder_types, do: @reminder_types
  def notification_channels, do: @notification_channels
  def recurrence_frequencies, do: @recurrence_frequencies
end
