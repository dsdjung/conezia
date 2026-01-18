defmodule Conezia.Workers.ReminderWorker do
  @moduledoc """
  Oban worker for processing due reminders and sending notifications.
  """
  use Oban.Worker, queue: :reminders, max_attempts: 3

  alias Conezia.Reminders
  alias Conezia.Reminders.Reminder
  alias Conezia.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"reminder_id" => reminder_id}}) do
    case Repo.get(Reminder, reminder_id) do
      nil ->
        {:error, :reminder_not_found}

      %Reminder{completed_at: completed_at} when not is_nil(completed_at) ->
        # Already completed, nothing to do
        :ok

      reminder ->
        send_notifications(reminder)
    end
  end

  def perform(%Oban.Job{args: %{"action" => "process_due"}}) do
    reminders = Reminders.list_due_reminders()

    Enum.each(reminders, fn reminder ->
      send_notifications(reminder)
    end)

    {:ok, %{processed: length(reminders)}}
  end

  defp send_notifications(reminder) do
    channels = reminder.notification_channels || ["in_app"]

    Enum.each(channels, fn channel ->
      case channel do
        "in_app" -> send_in_app_notification(reminder)
        "email" -> send_email_notification(reminder)
        "push" -> send_push_notification(reminder)
        _ -> :ok
      end
    end)

    :ok
  end

  defp send_in_app_notification(_reminder) do
    # TODO: Implement in-app notification via PubSub
    # Phoenix.PubSub.broadcast(Conezia.PubSub, "user:#{reminder.user_id}", {:reminder_due, reminder})
    :ok
  end

  defp send_email_notification(_reminder) do
    # TODO: Implement email sending via Swoosh or similar
    :ok
  end

  defp send_push_notification(_reminder) do
    # TODO: Implement push notifications via WebPush or similar
    :ok
  end

  @doc """
  Enqueue a job to process a specific reminder.
  """
  def enqueue(reminder_id) do
    %{reminder_id: reminder_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueue a job to process all due reminders.
  """
  def enqueue_due_processing do
    %{action: "process_due"}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedule recurring reminder processing every minute.
  """
  def schedule_recurring do
    %{action: "process_due"}
    |> new(schedule_in: 60)
    |> Oban.insert()
  end
end
