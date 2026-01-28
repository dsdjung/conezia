defmodule Conezia.Events do
  @moduledoc """
  The Events context for managing one-time and recurring events.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Events.{Event, EventEntity}
  alias Conezia.Reminders

  def get_event!(id), do: Repo.get!(Event, id)

  def get_event_for_user(id, user_id) do
    Event
    |> where([e], e.id == ^id and e.user_id == ^user_id)
    |> preload(:entities)
    |> Repo.one()
  end

  def list_events(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    type = Keyword.get(opts, :type)
    entity_id = Keyword.get(opts, :entity_id)
    date_from = Keyword.get(opts, :date_from)
    date_to = Keyword.get(opts, :date_to)

    query =
      from e in Event,
        where: e.user_id == ^user_id,
        order_by: [asc: e.starts_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:entities]

    events =
      query
      |> filter_by_type(type)
      |> filter_by_entity(entity_id)
      |> filter_by_date_range(date_from, date_to)
      |> Repo.all()

    {events, %{has_more: length(events) >= limit, next_cursor: nil}}
  end

  def upcoming_events(user_id, days_ahead \\ 30) do
    now = DateTime.utc_now()
    future = DateTime.add(now, days_ahead * 86400, :second)

    from(e in Event,
      where: e.user_id == ^user_id,
      where: e.starts_at >= ^now and e.starts_at <= ^future,
      order_by: [asc: e.starts_at],
      preload: [:entities]
    )
    |> Repo.all()
  end

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> maybe_create_reminder()
    |> maybe_link_entities(attrs)
  end

  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
    |> maybe_link_entities(attrs)
  end

  def delete_event(%Event{} = event) do
    if event.reminder_id do
      case Reminders.get_reminder(event.reminder_id) do
        nil -> :ok
        reminder -> Reminders.delete_reminder(reminder)
      end
    end

    Repo.delete(event)
  end

  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  # Entity linking

  def add_entity_to_event(event_id, entity_id, role \\ nil) do
    %EventEntity{}
    |> EventEntity.changeset(%{event_id: event_id, entity_id: entity_id, role: role})
    |> Repo.insert()
  end

  def remove_entity_from_event(event_id, entity_id) do
    from(ee in EventEntity,
      where: ee.event_id == ^event_id and ee.entity_id == ^entity_id
    )
    |> Repo.delete_all()
  end

  def list_events_for_entity(entity_id, user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(e in Event,
      join: ee in EventEntity, on: ee.event_id == e.id,
      where: ee.entity_id == ^entity_id and e.user_id == ^user_id,
      order_by: [asc: e.starts_at],
      limit: ^limit,
      preload: [:entities]
    )
    |> Repo.all()
  end

  # Private helpers

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [e], e.type == ^type)

  defp filter_by_entity(query, nil), do: query

  defp filter_by_entity(query, entity_id) do
    query
    |> join(:inner, [e], ee in EventEntity, on: ee.event_id == e.id)
    |> where([_e, ee], ee.entity_id == ^entity_id)
  end

  defp filter_by_date_range(query, nil, nil), do: query

  defp filter_by_date_range(query, date_from, date_to) do
    query
    |> maybe_filter_from(date_from)
    |> maybe_filter_to(date_to)
  end

  defp maybe_filter_from(query, nil), do: query
  defp maybe_filter_from(query, date_from), do: where(query, [e], e.starts_at >= ^date_from)

  defp maybe_filter_to(query, nil), do: query
  defp maybe_filter_to(query, date_to), do: where(query, [e], e.starts_at <= ^date_to)

  defp maybe_create_reminder({:ok, %Event{} = event}) do
    if DateTime.compare(event.starts_at, DateTime.utc_now()) == :gt do
      reminder_at = DateTime.add(event.starts_at, -14 * 86400, :second)

      if DateTime.compare(reminder_at, DateTime.utc_now()) == :gt do
        recurrence =
          cond do
            event.is_recurring -> event.recurrence_rule
            event.remind_yearly -> %{"freq" => "yearly"}
            true -> nil
          end

        case Reminders.create_reminder(%{
               type: "event",
               title: "Upcoming: #{event.title}",
               description: event.description,
               due_at: reminder_at,
               user_id: event.user_id,
               recurrence_rule: recurrence
             }) do
          {:ok, reminder} ->
            event
            |> Ecto.Changeset.change(reminder_id: reminder.id)
            |> Repo.update()

          {:error, _} ->
            {:ok, event}
        end
      else
        {:ok, event}
      end
    else
      {:ok, event}
    end
  end

  defp maybe_create_reminder(error), do: error

  defp maybe_link_entities({:ok, event}, attrs) do
    entity_ids = get_entity_ids(attrs)

    if entity_ids do
      # Clear existing links
      from(ee in EventEntity, where: ee.event_id == ^event.id)
      |> Repo.delete_all()

      # Add new links
      Enum.each(entity_ids, fn entity_id ->
        add_entity_to_event(event.id, entity_id)
      end)

      {:ok, Repo.preload(event, :entities, force: true)}
    else
      {:ok, event}
    end
  end

  defp maybe_link_entities(error, _attrs), do: error

  defp get_entity_ids(%{"entity_ids" => ids}) when is_list(ids), do: Enum.reject(ids, &(&1 == ""))
  defp get_entity_ids(%{entity_ids: ids}) when is_list(ids), do: Enum.reject(ids, &(&1 == ""))
  defp get_entity_ids(_), do: nil
end
