defmodule ConeziaWeb.EntityLive.Show do
  @moduledoc """
  LiveView for viewing and editing a single connection/entity.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Entities
  alias Conezia.Interactions
  alias Conezia.Reminders

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Connection not found")
         |> push_navigate(to: ~p"/connections")}

      entity ->
        socket =
          socket
          |> assign(:page_title, entity.name)
          |> assign(:entity, entity)
          |> assign(:interactions, list_interactions(entity.id, user.id))
          |> assign(:reminders, list_reminders(entity.id, user.id))

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:page_title, socket.assigns.entity.name)
  end

  defp apply_action(socket, :edit, _params) do
    socket
    |> assign(:page_title, "Edit #{socket.assigns.entity.name}")
  end

  @impl true
  def handle_event("delete", _params, socket) do
    entity = socket.assigns.entity

    case Entities.delete_entity(entity) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connection deleted successfully")
         |> push_navigate(to: ~p"/connections")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete connection")}
    end
  end

  @impl true
  def handle_info({ConeziaWeb.EntityLive.FormComponent, {:saved, entity}}, socket) do
    {:noreply,
     socket
     |> assign(:entity, entity)
     |> assign(:page_title, entity.name)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.back navigate={~p"/connections"}>Back to connections</.back>

      <div class="md:flex md:items-center md:justify-between">
        <div class="min-w-0 flex-1 flex items-center gap-4">
          <.avatar name={@entity.name} size={:xl} />
          <div>
            <h1 class="text-2xl font-bold leading-7 text-gray-900 sm:truncate sm:text-3xl sm:tracking-tight">
              {@entity.name}
            </h1>
            <div class="mt-1 flex items-center gap-2">
              <.badge color={entity_type_color(@entity.type)}>{@entity.type}</.badge>
              <.health_badge status={health_status(@entity)} />
            </div>
          </div>
        </div>
        <div class="mt-4 flex items-center gap-2 md:mt-0">
          <.link patch={~p"/connections/#{@entity.id}/edit"}>
            <.button class="bg-white text-gray-700 ring-1 ring-gray-300 hover:bg-gray-50">
              <span class="hero-pencil-square -ml-0.5 mr-1.5 h-5 w-5" />
              Edit
            </.button>
          </.link>
          <.button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this connection? This action cannot be undone."
            class="bg-red-600 hover:bg-red-700"
          >
            <span class="hero-trash -ml-0.5 mr-1.5 h-5 w-5" />
            Delete
          </.button>
        </div>
      </div>

      <!-- Info and details -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <!-- Main info -->
        <div class="lg:col-span-2 space-y-6">
          <.card>
            <:header>Details</:header>
            <.list>
              <:item :if={@entity.description} title="Description">{@entity.description}</:item>
              <:item title="Type">{String.capitalize(@entity.type || "Unknown")}</:item>
              <:item title="Health Score">{@entity.health_score || "Not calculated"}</:item>
              <:item :if={@entity.last_interaction_at} title="Last Interaction">
                {format_datetime(@entity.last_interaction_at)}
              </:item>
              <:item title="Created">{format_datetime(@entity.inserted_at)}</:item>
            </.list>
          </.card>

          <!-- Recent interactions -->
          <.card>
            <:header>
              <div class="flex items-center justify-between">
                <span>Recent Interactions</span>
              </div>
            </:header>
            <div :if={@interactions == []} class="py-8">
              <.empty_state>
                <:icon><span class="hero-chat-bubble-left-right h-10 w-10" /></:icon>
                <:title>No interactions yet</:title>
                <:description>Record your first interaction with this connection.</:description>
              </.empty_state>
            </div>
            <ul :if={@interactions != []} role="list" class="divide-y divide-gray-200">
              <li :for={interaction <- @interactions} class="py-4">
                <div class="flex items-start gap-3">
                  <span class={["hero-chat-bubble-left h-6 w-6 mt-0.5", interaction_type_color(interaction.type)]} />
                  <div class="min-w-0 flex-1">
                    <p class="text-sm font-medium text-gray-900">{interaction.type}</p>
                    <p :if={interaction.notes} class="mt-1 text-sm text-gray-500">{interaction.notes}</p>
                    <p class="mt-1 text-xs text-gray-400">{format_datetime(interaction.occurred_at)}</p>
                  </div>
                </div>
              </li>
            </ul>
          </.card>
        </div>

        <!-- Sidebar with reminders -->
        <div class="space-y-6">
          <.card>
            <:header>
              <div class="flex items-center justify-between">
                <span>Reminders</span>
                <.link navigate={~p"/reminders/new?entity_id=#{@entity.id}"} class="text-sm font-medium text-indigo-600 hover:text-indigo-500">
                  Add →
                </.link>
              </div>
            </:header>
            <div :if={@reminders == []} class="py-8">
              <.empty_state>
                <:icon><span class="hero-bell h-10 w-10" /></:icon>
                <:title>No reminders</:title>
                <:description>Set a reminder to stay in touch.</:description>
              </.empty_state>
            </div>
            <ul :if={@reminders != []} role="list" class="divide-y divide-gray-200">
              <li :for={reminder <- @reminders} class="py-3">
                <div class="flex items-center justify-between">
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-medium text-gray-900">{reminder.title}</p>
                    <p class="text-xs text-gray-500">{format_datetime(reminder.due_at)}</p>
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

      <.modal
        :if={@live_action == :edit}
        id="entity-modal"
        show
        on_cancel={JS.patch(~p"/connections/#{@entity.id}")}
      >
        <.live_component
          module={ConeziaWeb.EntityLive.FormComponent}
          id={@entity.id}
          title="Edit Connection"
          action={@live_action}
          entity={@entity}
          current_user={@current_user}
          patch={~p"/connections/#{@entity.id}"}
        />
      </.modal>
    </div>
    """
  end

  defp list_interactions(entity_id, user_id) do
    case Interactions.list_interactions(user_id, entity_id: entity_id, limit: 5) do
      {interactions, _meta} -> interactions
      interactions when is_list(interactions) -> interactions
    end
  end

  defp list_reminders(entity_id, user_id) do
    case Reminders.list_reminders_for_entity(entity_id, user_id, limit: 5) do
      {reminders, _meta} -> reminders
      reminders when is_list(reminders) -> reminders
    end
  end

  defp entity_type_color("person"), do: :blue
  defp entity_type_color("organization"), do: :indigo
  defp entity_type_color(_), do: :gray

  defp health_status(%{health_score: score}) when is_number(score) do
    cond do
      score >= 70 -> :healthy
      score >= 40 -> :attention
      true -> :critical
    end
  end

  defp health_status(_), do: :unknown

  defp interaction_type_color("call"), do: "text-green-500"
  defp interaction_type_color("email"), do: "text-blue-500"
  defp interaction_type_color("meeting"), do: "text-purple-500"
  defp interaction_type_color("message"), do: "text-indigo-500"
  defp interaction_type_color(_), do: "text-gray-500"

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
