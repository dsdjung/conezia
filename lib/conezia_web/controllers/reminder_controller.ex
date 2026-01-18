defmodule ConeziaWeb.ReminderController do
  @moduledoc """
  Controller for reminder management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Reminders
  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/reminders
  List all reminders for the current user.
  """
  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      status: params["status"],
      entity_id: params["entity_id"],
      type: params["type"],
      due_before: parse_datetime(params["due_before"]),
      due_after: parse_datetime(params["due_after"]),
      limit: parse_int(params["limit"], 50, 100),
      cursor: params["cursor"]
    ]

    {reminders, meta} = Reminders.list_reminders(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(reminders, &reminder_json/1),
      meta: meta
    })
  end

  @doc """
  GET /api/v1/reminders/:id
  Get a single reminder.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Reminders.get_reminder_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("reminder", id, conn.request_path))

      reminder ->
        conn
        |> put_status(:ok)
        |> json(%{data: reminder_json(reminder)})
    end
  end

  @doc """
  POST /api/v1/reminders
  Create a new reminder.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    # Verify the entity belongs to the user if entity_id is provided
    with {:ok, _} <- validate_entity_ownership(params["entity_id"], user.id) do
      attrs = Map.put(params, "user_id", user.id)

      case Reminders.create_reminder(attrs) do
        {:ok, reminder} ->
          conn
          |> put_status(:created)
          |> json(%{data: reminder_json(reminder)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
      end
    else
      {:error, :entity_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", params["entity_id"], conn.request_path))
    end
  end

  @doc """
  PUT /api/v1/reminders/:id
  Update a reminder.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Reminders.get_reminder_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("reminder", id, conn.request_path))

      reminder ->
        case Reminders.update_reminder(reminder, params) do
          {:ok, updated_reminder} ->
            conn
            |> put_status(:ok)
            |> json(%{data: reminder_json(updated_reminder)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/reminders/:id
  Delete a reminder.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Reminders.get_reminder_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("reminder", id, conn.request_path))

      reminder ->
        case Reminders.delete_reminder(reminder) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Reminder deleted"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/reminders/:id/snooze
  Snooze a reminder.
  """
  def snooze(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Reminders.get_reminder_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("reminder", id, conn.request_path))

      reminder ->
        snooze_until = determine_snooze_time(params)

        case Reminders.snooze_reminder(reminder, snooze_until) do
          {:ok, snoozed_reminder} ->
            conn
            |> put_status(:ok)
            |> json(%{data: reminder_json(snoozed_reminder)})

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/reminders/:id/complete
  Complete a reminder.
  """
  def complete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Reminders.get_reminder_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("reminder", id, conn.request_path))

      reminder ->
        case Reminders.complete_reminder(reminder) do
          {:ok, completed_reminder} ->
            conn
            |> put_status(:ok)
            |> json(%{data: reminder_json(completed_reminder)})

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  # Private helpers

  defp validate_entity_ownership(nil, _user_id), do: {:ok, nil}
  defp validate_entity_ownership(entity_id, user_id) do
    case Entities.get_entity_for_user(entity_id, user_id) do
      nil -> {:error, :entity_not_found}
      entity -> {:ok, entity}
    end
  end

  defp parse_int(nil, default, _max), do: default
  defp parse_int(val, default, max) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> min(num, max)
      :error -> default
    end
  end
  defp parse_int(val, _default, max) when is_integer(val), do: min(val, max)
  defp parse_int(_, default, _max), do: default

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp determine_snooze_time(%{"until" => until}) when is_binary(until) do
    case DateTime.from_iso8601(until) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp determine_snooze_time(%{"duration" => "1_hour"}) do
    DateTime.add(DateTime.utc_now(), 3600, :second)
  end

  defp determine_snooze_time(%{"duration" => "3_hours"}) do
    DateTime.add(DateTime.utc_now(), 3 * 3600, :second)
  end

  defp determine_snooze_time(%{"duration" => "tomorrow"}) do
    Date.utc_today()
    |> Date.add(1)
    |> DateTime.new!(~T[09:00:00], "Etc/UTC")
  end

  defp determine_snooze_time(%{"duration" => "next_week"}) do
    Date.utc_today()
    |> Date.add(7)
    |> DateTime.new!(~T[09:00:00], "Etc/UTC")
  end

  defp determine_snooze_time(_), do: nil

  defp reminder_json(reminder) do
    %{
      id: reminder.id,
      type: reminder.type,
      title: reminder.title,
      description: reminder.description,
      due_at: reminder.due_at,
      entity: entity_summary_json(reminder.entity),
      recurrence_rule: reminder.recurrence_rule,
      notification_channels: reminder.notification_channels,
      status: reminder_status(reminder),
      snoozed_until: reminder.snoozed_until,
      completed_at: reminder.completed_at,
      inserted_at: reminder.inserted_at,
      updated_at: reminder.updated_at
    }
  end

  defp entity_summary_json(nil), do: nil
  defp entity_summary_json(%Ecto.Association.NotLoaded{}), do: nil
  defp entity_summary_json(entity) do
    %{
      id: entity.id,
      name: entity.name,
      avatar_url: entity.avatar_url
    }
  end

  defp reminder_status(reminder) do
    cond do
      reminder.completed_at -> "completed"
      reminder.snoozed_until && DateTime.compare(reminder.snoozed_until, DateTime.utc_now()) == :gt -> "snoozed"
      DateTime.compare(reminder.due_at, DateTime.utc_now()) == :lt -> "overdue"
      true -> "pending"
    end
  end
end
