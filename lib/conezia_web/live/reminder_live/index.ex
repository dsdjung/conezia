defmodule ConeziaWeb.ReminderLive.Index do
  @moduledoc """
  LiveView for listing and managing reminders.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Reminders
  alias Conezia.Reminders.Reminder
  alias Conezia.Entities

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    entity_id = params["entity_id"]

    {reminders, _meta} = Reminders.list_reminders(user.id)

    socket =
      socket
      |> assign(:page_title, "Reminders")
      |> assign(:status_filter, "pending")
      |> assign(:entity_id, entity_id)
      |> stream(:reminders, reminders)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    entity_id = params["entity_id"]

    socket
    |> assign(:page_title, "New Reminder")
    |> assign(:reminder, %Reminder{entity_id: entity_id})
    |> assign(:entities, list_entities_for_select(socket.assigns.current_user.id))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    reminder = Reminders.get_reminder_for_user(id, user.id)

    if reminder do
      socket
      |> assign(:page_title, "Edit Reminder")
      |> assign(:reminder, reminder)
      |> assign(:entities, list_entities_for_select(user.id))
    else
      socket
      |> put_flash(:error, "Reminder not found")
      |> push_patch(to: ~p"/reminders")
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Reminders")
    |> assign(:reminder, nil)
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    user = socket.assigns.current_user
    status = if status == "", do: nil, else: status

    {reminders, _meta} = Reminders.list_reminders(user.id, status: status)

    socket =
      socket
      |> assign(:status_filter, status)
      |> stream(:reminders, reminders, reset: true)

    {:noreply, socket}
  end

  def handle_event("complete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    reminder = Reminders.get_reminder_for_user(id, user.id)

    case reminder do
      nil ->
        {:noreply, put_flash(socket, :error, "Reminder not found")}

      reminder ->
        case Reminders.complete_reminder(reminder) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> stream_insert(:reminders, updated)
             |> put_flash(:info, "Reminder completed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to complete reminder")}
        end
    end
  end

  def handle_event("snooze", %{"id" => id, "duration" => duration}, socket) do
    user = socket.assigns.current_user
    reminder = Reminders.get_reminder_for_user(id, user.id)

    case reminder do
      nil ->
        {:noreply, put_flash(socket, :error, "Reminder not found")}

      reminder ->
        case Reminders.snooze_reminder_by_duration(reminder, duration) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> stream_insert(:reminders, updated)
             |> put_flash(:info, "Reminder snoozed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to snooze reminder")}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    reminder = Reminders.get_reminder_for_user(id, user.id)

    case reminder do
      nil ->
        {:noreply, put_flash(socket, :error, "Reminder not found")}

      reminder ->
        {:ok, _} = Reminders.delete_reminder(reminder)

        {:noreply,
         socket
         |> stream_delete(:reminders, reminder)
         |> put_flash(:info, "Reminder deleted")}
    end
  end

  @impl true
  def handle_info({ConeziaWeb.ReminderLive.FormComponent, {:saved, reminder}}, socket) do
    {:noreply, stream_insert(socket, :reminders, reminder, at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Reminders
        <:subtitle>Stay on top of important follow-ups and events</:subtitle>
        <:actions>
          <.link patch={~p"/reminders/new"}>
            <.button>
              <span class="hero-plus -ml-0.5 mr-1.5 h-5 w-5" />
              Add Reminder
            </.button>
          </.link>
        </:actions>
      </.header>

      <!-- Filters -->
      <div class="flex items-center gap-4">
        <form phx-change="filter_status">
          <select
            name="status"
            class="block rounded-lg border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
          >
            <option value="" selected={is_nil(@status_filter)}>All Reminders</option>
            <option value="pending" selected={@status_filter == "pending"}>Pending</option>
            <option value="overdue" selected={@status_filter == "overdue"}>Overdue</option>
            <option value="snoozed" selected={@status_filter == "snoozed"}>Snoozed</option>
            <option value="completed" selected={@status_filter == "completed"}>Completed</option>
          </select>
        </form>
      </div>

      <!-- Reminder list -->
      <div class="bg-white shadow ring-1 ring-gray-200 rounded-lg overflow-hidden">
        <ul id="reminders" phx-update="stream" role="list" class="divide-y divide-gray-200">
          <li
            :for={{dom_id, reminder} <- @streams.reminders}
            id={dom_id}
            class={["px-4 py-4 sm:px-6", reminder.completed_at && "bg-gray-50"]}
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center min-w-0 gap-4">
                <span class={[
                  "hero-bell h-8 w-8 flex-shrink-0",
                  reminder_status_color(reminder)
                ]} />
                <div class="min-w-0 flex-1">
                  <p class={["text-sm font-medium", reminder.completed_at && "text-gray-500 line-through", !reminder.completed_at && "text-gray-900"]}>
                    {reminder.title}
                  </p>
                  <p :if={reminder.description} class="mt-1 text-sm text-gray-500 truncate">
                    {reminder.description}
                  </p>
                  <div class="mt-2 flex items-center gap-2 text-xs text-gray-500">
                    <span>Due: {format_datetime(reminder.due_at)}</span>
                    <span :if={reminder.entity}>
                      • <.link navigate={~p"/connections/#{reminder.entity.id}"} class="text-indigo-600 hover:text-indigo-500">
                        {reminder.entity.name}
                      </.link>
                    </span>
                  </div>
                </div>
              </div>

              <div class="flex items-center gap-2 ml-4">
                <.badge color={reminder_type_color(reminder.type)}>
                  {humanize_type(reminder.type)}
                </.badge>

                <div :if={is_nil(reminder.completed_at)} class="flex items-center gap-1">
                  <button
                    phx-click="complete"
                    phx-value-id={reminder.id}
                    title="Mark as complete"
                    class="p-1 text-gray-400 hover:text-green-500"
                  >
                    <span class="hero-check-circle h-5 w-5" />
                  </button>

                  <div class="relative">
                    <button
                      phx-click={JS.toggle(to: "#snooze-#{reminder.id}")}
                      title="Snooze"
                      class="p-1 text-gray-400 hover:text-indigo-500"
                    >
                      <span class="hero-clock h-5 w-5" />
                    </button>
                    <div
                      id={"snooze-#{reminder.id}"}
                      class="hidden absolute right-0 z-10 mt-2 w-40 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5"
                    >
                      <button
                        phx-click="snooze"
                        phx-value-id={reminder.id}
                        phx-value-duration="1_hour"
                        class="block w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        1 hour
                      </button>
                      <button
                        phx-click="snooze"
                        phx-value-id={reminder.id}
                        phx-value-duration="3_hours"
                        class="block w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        3 hours
                      </button>
                      <button
                        phx-click="snooze"
                        phx-value-id={reminder.id}
                        phx-value-duration="tomorrow"
                        class="block w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        Tomorrow
                      </button>
                      <button
                        phx-click="snooze"
                        phx-value-id={reminder.id}
                        phx-value-duration="next_week"
                        class="block w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        Next week
                      </button>
                    </div>
                  </div>

                  <.link patch={~p"/reminders/#{reminder.id}/edit"} class="p-1 text-gray-400 hover:text-gray-500">
                    <span class="hero-pencil-square h-5 w-5" />
                  </.link>
                </div>

                <button
                  phx-click="delete"
                  phx-value-id={reminder.id}
                  data-confirm="Are you sure you want to delete this reminder?"
                  class="p-1 text-gray-400 hover:text-red-500"
                >
                  <span class="hero-trash h-5 w-5" />
                </button>
              </div>
            </div>
          </li>
        </ul>

        <div :if={@streams.reminders.inserts == []} class="py-12">
          <.empty_state>
            <:icon><span class="hero-bell h-12 w-12" /></:icon>
            <:title>No reminders found</:title>
            <:description>
              {if @status_filter, do: "Try adjusting your filter.", else: "Create your first reminder to stay on top of important follow-ups."}
            </:description>
            <:action :if={is_nil(@status_filter)}>
              <.link patch={~p"/reminders/new"}>
                <.button>Add Reminder</.button>
              </.link>
            </:action>
          </.empty_state>
        </div>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="reminder-modal"
        show
        on_cancel={JS.patch(~p"/reminders")}
      >
        <.live_component
          module={ConeziaWeb.ReminderLive.FormComponent}
          id={@reminder.id || :new}
          title={@page_title}
          action={@live_action}
          reminder={@reminder}
          entities={@entities}
          current_user={@current_user}
          patch={~p"/reminders"}
        />
      </.modal>
    </div>
    """
  end

  defp list_entities_for_select(user_id) do
    {entities, _meta} = Entities.list_entities(user_id, limit: 10_000)
    Enum.map(entities, &{&1.name, &1.id})
  end

  defp reminder_status_color(reminder) do
    cond do
      reminder.completed_at -> "text-green-500"
      reminder.snoozed_until && DateTime.compare(reminder.snoozed_until, DateTime.utc_now()) == :gt -> "text-yellow-500"
      DateTime.compare(reminder.due_at, DateTime.utc_now()) == :lt -> "text-red-500"
      true -> "text-gray-400"
    end
  end

  defp reminder_type_color("follow_up"), do: :blue
  defp reminder_type_color("birthday"), do: :indigo
  defp reminder_type_color("anniversary"), do: :indigo
  defp reminder_type_color("health_alert"), do: :red
  defp reminder_type_color(_), do: :gray

  defp humanize_type(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize_type(_), do: "Reminder"

  defp format_datetime(nil), do: "Not set"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end
end
