defmodule ConeziaWeb.EventLive.Index do
  @moduledoc """
  LiveView for managing events.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Events
  alias Conezia.Events.Event
  alias Conezia.Entities

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    self_entity = Entities.get_self_entity(user.id)
    {events, meta} = Events.list_events(user.id, limit: @page_size)
    total_count = Events.count_events(user.id)

    socket =
      socket
      |> assign(:page_title, "Events")
      |> assign(:search, "")
      |> assign(:type_filter, nil)
      |> assign(:sort, "date_asc")
      |> assign(:involvement, "all")
      |> assign(:self_entity_id, self_entity && self_entity.id)
      |> assign(:page, 0)
      |> assign(:has_more, meta.has_more)
      |> assign(:loading, false)
      |> assign(:total_count, total_count)
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
    |> assign(:entities, [])
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    event = Events.get_event_for_user(id, user.id)

    if event do
      selected_entities =
        case event do
          %{entities: entities} when is_list(entities) ->
            Enum.map(entities, fn e ->
              label = if e.is_self, do: "#{e.name} (me)", else: e.name
              {label, e.id}
            end)
          _ -> []
        end

      socket
      |> assign(:page_title, "Edit Event")
      |> assign(:event, event)
      |> assign(:entities, selected_entities)
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
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, load_events(assign(socket, :search, search))}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    type = if type == "", do: nil, else: type
    {:noreply, load_events(assign(socket, :type_filter, type))}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    {:noreply, load_events(assign(socket, :sort, sort))}
  end

  def handle_event("filter_involvement", %{"involvement" => involvement}, socket) do
    {:noreply, load_events(assign(socket, :involvement, involvement))}
  end

  def handle_event("load-more", _params, socket) do
    if socket.assigns.loading or not socket.assigns.has_more do
      {:noreply, socket}
    else
      user = socket.assigns.current_user
      next_page = socket.assigns.page + 1
      offset = next_page * @page_size

      socket = assign(socket, :loading, true)

      {events, meta} = Events.list_events(user.id,
        search: socket.assigns.search,
        type: socket.assigns.type_filter,
        sort: socket.assigns.sort,
        entity_id: involvement_entity_id(socket.assigns),
        limit: @page_size,
        offset: offset
      )

      {:noreply,
       socket
       |> assign(:page, next_page)
       |> assign(:has_more, meta.has_more)
       |> assign(:loading, false)
       |> stream(:events, events)}
    end
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
        <div class="px-4 py-3 border-b border-gray-200 bg-gray-50 space-y-3">
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-semibold text-gray-900">
              {@total_count} {if @total_count == 1, do: "event", else: "events"}
            </h3>
            <div class="flex items-center gap-2">
              <form :if={@self_entity_id} phx-change="filter_involvement">
                <select
                  name="involvement"
                  class="block rounded-md border-gray-300 text-xs focus:border-indigo-500 focus:ring-indigo-500"
                >
                  <option value="all" selected={@involvement == "all"}>All Events</option>
                  <option value="mine" selected={@involvement == "mine"}>My Events</option>
                </select>
              </form>
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
              <form phx-change="sort">
                <select
                  name="sort"
                  class="block rounded-md border-gray-300 text-xs focus:border-indigo-500 focus:ring-indigo-500"
                >
                  <option value="date_asc" selected={@sort == "date_asc"}>Date (earliest)</option>
                  <option value="date_desc" selected={@sort == "date_desc"}>Date (latest)</option>
                  <option value="title" selected={@sort == "title"}>Title A-Z</option>
                  <option value="newest" selected={@sort == "newest"}>Newest first</option>
                  <option value="oldest" selected={@sort == "oldest"}>Oldest first</option>
                </select>
              </form>
            </div>
          </div>
          <form phx-change="search">
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Search events..."
              phx-debounce="300"
              class="block w-full rounded-md border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
            />
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
                  <.badge :if={event.sync_status == "synced"} color={:green}>
                    <span class="hero-arrow-path h-3 w-3 mr-0.5" />Synced
                  </.badge>
                  <.badge :if={event.sync_status == "pending_push"} color={:yellow}>
                    <span class="hero-arrow-up-tray h-3 w-3 mr-0.5" />Pending
                  </.badge>
                  <.badge :if={event.sync_status == "conflict"} color={:red}>
                    <span class="hero-exclamation-triangle h-3 w-3 mr-0.5" />Conflict
                  </.badge>
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
                <div
                  :if={event.latitude && event.longitude}
                  id={"event-map-#{event.id}"}
                  phx-hook="GoogleMap"
                  phx-update="ignore"
                  data-lat={event.latitude}
                  data-lng={event.longitude}
                  class="mt-2 h-32 w-full rounded-lg border border-gray-200"
                >
                </div>
                <div :if={event.entities != []} class="mt-1 flex items-center gap-1 text-xs text-gray-500">
                  <span class="hero-users h-4 w-4" />
                  <span :for={entity <- event.entities} class="inline-flex items-center gap-0.5">
                    <.link navigate={~p"/connections/#{entity.id}"} class="text-indigo-600 hover:text-indigo-500">
                      {entity.name}
                    </.link>
                    <span :if={entity.is_self} class="text-gray-400 text-xs">(me)</span>
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
              {if @search != "" || @type_filter, do: "No events match your filters.", else: "No events yet. Create your first event!"}
            </p>
          </div>
        </div>

        <div :if={@has_more} id="events-infinite-scroll" phx-hook="InfiniteScroll" class="py-4 flex justify-center">
          <div :if={@loading} class="text-sm text-gray-500">Loading more...</div>
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

  defp load_events(socket) do
    user = socket.assigns.current_user
    entity_filter = involvement_entity_id(socket.assigns)

    {events, meta} = Events.list_events(user.id,
      search: socket.assigns.search,
      type: socket.assigns.type_filter,
      sort: socket.assigns.sort,
      entity_id: entity_filter,
      limit: @page_size
    )

    total_count = Events.count_events(user.id,
      search: socket.assigns.search,
      type: socket.assigns.type_filter,
      entity_id: entity_filter
    )

    socket
    |> assign(:page, 0)
    |> assign(:has_more, meta.has_more)
    |> assign(:total_count, total_count)
    |> stream(:events, events, reset: true)
  end

  defp involvement_entity_id(%{involvement: "mine", self_entity_id: id}) when not is_nil(id), do: id
  defp involvement_entity_id(_), do: nil

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
  defp type_color("wedding"), do: :indigo
  defp type_color("memorial"), do: :gray
  defp type_color(_), do: :gray
end
