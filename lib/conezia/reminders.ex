defmodule Conezia.Reminders do
  @moduledoc """
  The Reminders context for managing follow-ups and notifications.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Reminders.Reminder

  def get_reminder(id), do: Repo.get(Reminder, id)

  def get_reminder!(id), do: Repo.get!(Reminder, id)

  def get_reminder_for_user(id, user_id) do
    Reminder
    |> where([r], r.id == ^id and r.user_id == ^user_id)
    |> Repo.one()
  end

  def list_reminders(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    status = Keyword.get(opts, :status)
    entity_id = Keyword.get(opts, :entity_id)
    type = Keyword.get(opts, :type)
    due_before = Keyword.get(opts, :due_before)
    due_after = Keyword.get(opts, :due_after)

    query = from r in Reminder,
      where: r.user_id == ^user_id,
      limit: ^limit,
      offset: ^offset,
      order_by: [asc: r.due_at],
      preload: [:entity]

    reminders = query
    |> filter_by_status(status)
    |> filter_by_entity_id(entity_id)
    |> filter_by_type(type)
    |> filter_by_due_before(due_before)
    |> filter_by_due_after(due_after)
    |> Repo.all()

    {reminders, %{has_more: length(reminders) >= limit, next_cursor: nil}}
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, "pending") do
    now = DateTime.utc_now()
    where(query, [r], is_nil(r.completed_at) and (is_nil(r.snoozed_until) or r.snoozed_until < ^now))
  end
  defp filter_by_status(query, "completed"), do: where(query, [r], not is_nil(r.completed_at))
  defp filter_by_status(query, "snoozed") do
    now = DateTime.utc_now()
    where(query, [r], is_nil(r.completed_at) and r.snoozed_until > ^now)
  end
  defp filter_by_status(query, "overdue") do
    now = DateTime.utc_now()
    where(query, [r], is_nil(r.completed_at) and r.due_at < ^now and (is_nil(r.snoozed_until) or r.snoozed_until < ^now))
  end
  defp filter_by_status(query, _), do: query

  defp filter_by_entity_id(query, nil), do: query
  defp filter_by_entity_id(query, entity_id), do: where(query, [r], r.entity_id == ^entity_id)

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [r], r.type == ^type)

  defp filter_by_due_before(query, nil), do: query
  defp filter_by_due_before(query, due_before) do
    case DateTime.from_iso8601(due_before) do
      {:ok, datetime, _} -> where(query, [r], r.due_at < ^datetime)
      _ -> query
    end
  end

  defp filter_by_due_after(query, nil), do: query
  defp filter_by_due_after(query, due_after) do
    case DateTime.from_iso8601(due_after) do
      {:ok, datetime, _} -> where(query, [r], r.due_at > ^datetime)
      _ -> query
    end
  end

  def list_due_reminders(before_datetime \\ nil) do
    before = before_datetime || DateTime.utc_now()

    Reminder
    |> where([r], is_nil(r.completed_at))
    |> where([r], r.due_at <= ^before)
    |> where([r], is_nil(r.snoozed_until) or r.snoozed_until < ^before)
    |> preload([:user, :entity])
    |> Repo.all()
  end

  def create_reminder(attrs) do
    %Reminder{}
    |> Reminder.changeset(attrs)
    |> Repo.insert()
  end

  def update_reminder(%Reminder{} = reminder, attrs) do
    reminder
    |> Reminder.changeset(attrs)
    |> Repo.update()
  end

  def delete_reminder(%Reminder{} = reminder) do
    Repo.delete(reminder)
  end

  def snooze_reminder(%Reminder{} = reminder, until) do
    reminder
    |> Reminder.snooze_changeset(until)
    |> Repo.update()
  end

  def snooze_reminder_by_duration(%Reminder{} = reminder, duration) do
    until = calculate_snooze_until(duration)

    reminder
    |> Reminder.snooze_changeset(until)
    |> Repo.update()
  end

  defp calculate_snooze_until("1_hour"), do: DateTime.add(DateTime.utc_now(), 3600, :second)
  defp calculate_snooze_until("3_hours"), do: DateTime.add(DateTime.utc_now(), 10800, :second)
  defp calculate_snooze_until("tomorrow") do
    DateTime.utc_now()
    |> DateTime.add(86400, :second)
    |> DateTime.truncate(:second)
    |> Map.put(:hour, 9)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
  end
  defp calculate_snooze_until("next_week"), do: DateTime.add(DateTime.utc_now(), 604800, :second)
  defp calculate_snooze_until(_), do: DateTime.add(DateTime.utc_now(), 3600, :second)

  def complete_reminder(%Reminder{} = reminder) do
    reminder
    |> Reminder.complete_changeset()
    |> Repo.update()
  end

  def list_reminders_for_entity(entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    reminders = from(r in Reminder,
      where: r.entity_id == ^entity_id,
      order_by: [asc: r.due_at],
      limit: ^limit,
      preload: [:entity]
    )
    |> Repo.all()

    {reminders, %{has_more: false, next_cursor: nil}}
  end
end
