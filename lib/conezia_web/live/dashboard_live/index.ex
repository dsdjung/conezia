defmodule ConeziaWeb.DashboardLive.Index do
  @moduledoc """
  Dashboard LiveView showing overview of contacts and relationship health.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Entities
  alias Conezia.Reminders

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign_stats(user)
      |> assign_recent_entities(user)
      |> assign_upcoming_reminders(user)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Welcome back!
        <:subtitle>Here's an overview of your relationships</:subtitle>
      </.header>

      <!-- Stats Cards -->
      <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
        <.stats_card
          title="Total Contacts"
          value={@stats.total_contacts}
          icon="hero-users"
        />
        <.stats_card
          title="Healthy"
          value={@stats.healthy_count}
          icon="hero-face-smile"
          color="green"
        />
        <.stats_card
          title="Needs Attention"
          value={@stats.attention_count}
          icon="hero-exclamation-triangle"
          color="yellow"
        />
        <.stats_card
          title="Upcoming Reminders"
          value={@stats.upcoming_reminders}
          icon="hero-bell"
          color="indigo"
        />
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <!-- Recent Contacts -->
        <.card>
          <:header>
            <div class="flex items-center justify-between">
              <span>Recent Contacts</span>
              <.link navigate={~p"/contacts"} class="text-sm font-medium text-indigo-600 hover:text-indigo-500">
                View all →
              </.link>
            </div>
          </:header>
          <div :if={@recent_entities == []} class="py-8">
            <.empty_state>
              <:icon><span class="hero-users h-12 w-12" /></:icon>
              <:title>No contacts yet</:title>
              <:description>Get started by adding your first contact.</:description>
              <:action>
                <.link navigate={~p"/contacts/new"}>
                  <.button>Add Contact</.button>
                </.link>
              </:action>
            </.empty_state>
          </div>
          <ul :if={@recent_entities != []} role="list" class="divide-y divide-gray-200">
            <li :for={entity <- @recent_entities} class="py-4">
              <.link navigate={~p"/contacts/#{entity.id}"} class="flex items-center space-x-4 hover:bg-gray-50 -mx-4 px-4 py-2 rounded-lg">
                <.avatar name={entity.name} size={:md} />
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-medium text-gray-900">{entity.name}</p>
                  <p class="truncate text-sm text-gray-500">{entity.description || "No description"}</p>
                </div>
                <.health_badge status={health_status(entity)} />
              </.link>
            </li>
          </ul>
        </.card>

        <!-- Upcoming Reminders -->
        <.card>
          <:header>
            <div class="flex items-center justify-between">
              <span>Upcoming Reminders</span>
              <.link navigate={~p"/reminders"} class="text-sm font-medium text-indigo-600 hover:text-indigo-500">
                View all →
              </.link>
            </div>
          </:header>
          <div :if={@upcoming_reminders == []} class="py-8">
            <.empty_state>
              <:icon><span class="hero-bell h-12 w-12" /></:icon>
              <:title>No upcoming reminders</:title>
              <:description>You're all caught up! Create a reminder to stay in touch.</:description>
              <:action>
                <.link navigate={~p"/reminders/new"}>
                  <.button>Add Reminder</.button>
                </.link>
              </:action>
            </.empty_state>
          </div>
          <ul :if={@upcoming_reminders != []} role="list" class="divide-y divide-gray-200">
            <li :for={reminder <- @upcoming_reminders} class="py-4">
              <div class="flex items-center space-x-4">
                <div class="flex-shrink-0">
                  <span class="hero-bell h-8 w-8 text-gray-400" />
                </div>
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-medium text-gray-900">{reminder.title}</p>
                  <p class="truncate text-sm text-gray-500">
                    Due: {format_datetime(reminder.due_at)}
                  </p>
                </div>
                <.badge color={reminder_type_color(reminder.type)}>
                  {humanize_type(reminder.type)}
                </.badge>
              </div>
            </li>
          </ul>
        </.card>
      </div>
    </div>
    """
  end

  # Component for stats card
  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "gray"

  defp stats_card(assigns) do
    color_classes = %{
      "gray" => "bg-gray-100 text-gray-600",
      "green" => "bg-green-100 text-green-600",
      "yellow" => "bg-yellow-100 text-yellow-600",
      "red" => "bg-red-100 text-red-600",
      "indigo" => "bg-indigo-100 text-indigo-600"
    }

    assigns = assign(assigns, :color_class, Map.get(color_classes, assigns.color, "bg-gray-100 text-gray-600"))

    ~H"""
    <div class="overflow-hidden rounded-lg bg-white px-4 py-5 shadow sm:p-6">
      <dt class="flex items-center gap-2">
        <div class={["rounded-md p-2", @color_class]}>
          <span class={[@icon, "h-5 w-5"]} />
        </div>
        <span class="truncate text-sm font-medium text-gray-500">{@title}</span>
      </dt>
      <dd class="mt-3 text-3xl font-semibold tracking-tight text-gray-900">
        {@value}
      </dd>
    </div>
    """
  end

  defp assign_stats(socket, user) do
    # Get counts from entities context
    total = Entities.count_user_entities(user.id)

    # Get health-based counts
    {healthy, attention} = get_health_counts(user.id)

    # Get upcoming reminder count
    upcoming = Reminders.count_upcoming_reminders(user.id)

    stats = %{
      total_contacts: total,
      healthy_count: healthy,
      attention_count: attention,
      upcoming_reminders: upcoming
    }

    assign(socket, :stats, stats)
  end

  defp get_health_counts(user_id) do
    entities = Entities.list_entities(user_id, limit: 1000)

    Enum.reduce(entities, {0, 0}, fn entity, {healthy, attention} ->
      case health_status(entity) do
        :healthy -> {healthy + 1, attention}
        :attention -> {healthy, attention + 1}
        :critical -> {healthy, attention + 1}
        _ -> {healthy, attention}
      end
    end)
  end

  defp assign_recent_entities(socket, user) do
    entities = Entities.list_entities(user.id, limit: 5)
    assign(socket, :recent_entities, entities)
  end

  defp assign_upcoming_reminders(socket, user) do
    reminders = Reminders.list_upcoming_reminders(user.id, limit: 5)
    assign(socket, :upcoming_reminders, reminders)
  end

  defp health_status(%{health_score: score}) when is_number(score) do
    cond do
      score >= 70 -> :healthy
      score >= 40 -> :attention
      true -> :critical
    end
  end

  defp health_status(_), do: :unknown

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

  defp format_datetime(nil), do: "No date"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end
end
