defmodule ConeziaWeb.EventLive.Index do
  @moduledoc """
  LiveView for managing events.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Events
  alias Conezia.Events.Event
  alias Conezia.Entities

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    {events, _meta} = Events.list_events(user.id)

    socket =
      socket
      |> assign(:page_title, "Events")
      |> assign(:type_filter, nil)
      |> stream(:events, events)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Event")
    |> assign(:event, %Event{})
    |> assign(:entities, list_entities_for_select(socket.assigns.current_user.id))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    event = Events.get_event_for_user(id, user.id)

    if event do
      socket
      |> assign(:page_title, "Edit Event")
      |> assign(:event, event)
      |> assign(:entities, list_entities_for_select(user.id))
    else
      socket
      |> put_flash(:error, "Event not found")
      |> push_patch(to: ~p"/events")
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Events")
    |> assign(:event, nil)
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    user = socket.assigns.current_user
    type = if type == "", do: nil, else: type

    {events, _meta} = Events.list_events(user.id, type: type)

    {:noreply,
     socket
     |> assign(:type_filter, type)
     |> stream(:events, events, reset: true)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    event = Events.get_event_for_user(id, user.id)

    case event do
      nil ->
        {:noreply, put_flash(socket, :error, "Event not found")}

      event ->
        {:ok, _} = Events.delete_event(event)

        {:noreply,
         socket
         |> stream_delete(:events, event)
         |> put_flash(:info, "Event deleted")}
    end
  end

  @impl true
  def handle_info({ConeziaWeb.EventLive.FormComponent, {:saved, event}}, socket) do
    {:noreply, stream_insert(socket, :events, event, at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Events
        <:subtitle>Track one-time and recurring events with your connections</:subtitle>
        <:actions>
          <.link patch={~p"/events/new"}>
            <.button>New Event</.button>
          </.link>
        </:actions>
      </.header>

      <div class="bg-white shadow ring-1 ring-gray-200 rounded-lg overflow-hidden">
        <div class="px-4 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between">
          <h3 class="text-sm font-semibold text-gray-900">All Events</h3>
          <form phx-change="filter_type">
            <select
              name="type"
              class="block rounded-md border-gray-300 text-xs focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option value="" selected={is_nil(@type_filter)}>All Types</option>
              <option :for={type <- Event.valid_types()} value={type} selected={@type_filter == type}>
                {humanize(type)}
              </option>
            </select>
          </form>
        </div>

        <ul id="events" phx-update="stream" role="list" class="divide-y divide-gray-200">
          <li :for={{dom_id, event} <- @streams.events} id={dom_id} class="px-4 py-4 hover:bg-gray-50 group">
            <div class="flex items-start justify-between">
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <p class="text-sm font-medium text-gray-900">{event.title}</p>
                  <.badge color={type_color(event.type)}>{humanize(event.type)}</.badge>
                  <span :if={event.is_recurring} class="text-xs text-indigo-500 font-medium">Recurring</span>
                </div>
                <div class="mt-1 flex items-center gap-3 text-xs text-gray-500">
                  <span class="flex items-center gap-1">
                    <span class="hero-calendar h-4 w-4" />
                    {format_datetime(event.starts_at, event.all_day)}
                  </span>
                  <span :if={event.location} class="flex items-center gap-1">
                    <span class="hero-map-pin h-4 w-4" />
                    {event.location}
                  </span>
                </div>
                <div :if={event.entities != []} class="mt-1 flex items-center gap-1 text-xs text-gray-500">
                  <span class="hero-users h-4 w-4" />
                  <span :for={entity <- event.entities} class="inline-flex">
                    <.link navigate={~p"/connections/#{entity.id}"} class="text-indigo-600 hover:text-indigo-500">
                      {entity.name}
                    </.link>
                  </span>
                </div>
              </div>

              <div class="flex items-center gap-2 ml-4 opacity-0 group-hover:opacity-100 transition-opacity">
                <.link patch={~p"/events/#{event.id}/edit"} class="p-1 text-gray-400 hover:text-gray-500">
                  <span class="hero-pencil-square h-5 w-5" />
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={event.id}
                  data-confirm="Delete this event?"
                  class="p-1 text-gray-400 hover:text-red-500"
                >
                  <span class="hero-trash h-5 w-5" />
                </button>
              </div>
            </div>
          </li>
        </ul>

        <div :if={@streams.events.inserts == []} class="py-8">
          <div class="text-center">
            <span class="hero-calendar h-10 w-10 text-gray-400 mx-auto" />
            <p class="mt-2 text-sm text-gray-500">
              {if @type_filter, do: "No events match this filter.", else: "No events yet. Create your first event!"}
            </p>
          </div>
        </div>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="event-modal"
        show
        on_cancel={JS.patch(~p"/events")}
      >
        <.live_component
          module={ConeziaWeb.EventLive.FormComponent}
          id={@event.id || :new}
          title={@page_title}
          action={@live_action}
          event={@event}
          entities={@entities}
          current_user={@current_user}
          patch={~p"/events"}
        />
      </.modal>
    </div>
    """
  end

  defp list_entities_for_select(user_id) do
    {entities, _meta} = Entities.list_entities(user_id, limit: 100)
    Enum.map(entities, &{&1.name, &1.id})
  end

  defp format_datetime(datetime, true), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_datetime(datetime, _), do: Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")

  defp humanize(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
  end

  defp type_color("birthday"), do: :red
  defp type_color("anniversary"), do: :indigo
  defp type_color("holiday"), do: :red
  defp type_color("meeting"), do: :blue
  defp type_color("dinner"), do: :yellow
  defp type_color("party"), do: :green
  defp type_color(_), do: :gray
end
