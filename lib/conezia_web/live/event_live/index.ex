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
    # Default to showing only upcoming events (today and future)
    {events, meta} = Events.list_events(user.id, limit: @page_size, time_filter: "upcoming")
    total_count = Events.count_events(user.id, time_filter: "upcoming")

    # Calendar view state
    today = Date.utc_today()

    socket =
      socket
      |> assign(:page_title, "Events")
      |> assign(:search, "")
      |> assign(:type_filter, nil)
      |> assign(:sort, "date_asc")
      |> assign(:involvement, "all")
      |> assign(:time_filter, "upcoming")
      |> assign(:view_mode, "list")
      |> assign(:calendar_year, today.year)
      |> assign(:calendar_month, today.month)
      |> assign(:calendar_events, %{})
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

  def handle_event("filter_time", %{"time" => time_filter}, socket) do
    {:noreply, load_events(assign(socket, :time_filter, time_filter))}
  end

  def handle_event("switch_view", %{"view" => view_mode}, socket) do
    socket = assign(socket, :view_mode, view_mode)

    socket =
      if view_mode == "calendar" do
        load_calendar_events(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("prev_month", _params, socket) do
    {year, month} = prev_month(socket.assigns.calendar_year, socket.assigns.calendar_month)

    socket =
      socket
      |> assign(:calendar_year, year)
      |> assign(:calendar_month, month)
      |> load_calendar_events()

    {:noreply, socket}
  end

  def handle_event("next_month", _params, socket) do
    {year, month} = next_month(socket.assigns.calendar_year, socket.assigns.calendar_month)

    socket =
      socket
      |> assign(:calendar_year, year)
      |> assign(:calendar_month, month)
      |> load_calendar_events()

    {:noreply, socket}
  end

  def handle_event("today", _params, socket) do
    today = Date.utc_today()

    socket =
      socket
      |> assign(:calendar_year, today.year)
      |> assign(:calendar_month, today.month)
      |> load_calendar_events()

    {:noreply, socket}
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
        time_filter: socket.assigns.time_filter,
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
            <div class="flex items-center gap-3">
              <h3 class="text-sm font-semibold text-gray-900">
                {@total_count} {if @total_count == 1, do: "event", else: "events"}
              </h3>
              <%!-- View toggle --%>
              <div class="flex rounded-md shadow-sm">
                <button
                  type="button"
                  phx-click="switch_view"
                  phx-value-view="list"
                  class={"relative inline-flex items-center rounded-l-md px-2 py-1 text-xs font-medium ring-1 ring-inset ring-gray-300 focus:z-10 #{if @view_mode == "list", do: "bg-indigo-600 text-white", else: "bg-white text-gray-900 hover:bg-gray-50"}"}
                >
                  <span class="hero-list-bullet h-4 w-4" />
                </button>
                <button
                  type="button"
                  phx-click="switch_view"
                  phx-value-view="calendar"
                  class={"relative -ml-px inline-flex items-center rounded-r-md px-2 py-1 text-xs font-medium ring-1 ring-inset ring-gray-300 focus:z-10 #{if @view_mode == "calendar", do: "bg-indigo-600 text-white", else: "bg-white text-gray-900 hover:bg-gray-50"}"}
                >
                  <span class="hero-calendar-days h-4 w-4" />
                </button>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <form :if={@view_mode == "list"} phx-change="filter_time">
                <select
                  name="time"
                  class="block rounded-md border-gray-300 text-xs focus:border-indigo-500 focus:ring-indigo-500"
                >
                  <option value="upcoming" selected={@time_filter == "upcoming"}>Upcoming</option>
                  <option value="all" selected={@time_filter == "all"}>All Time</option>
                </select>
              </form>
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
              <form :if={@view_mode == "list"} phx-change="sort">
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
          <form :if={@view_mode == "list"} phx-change="search">
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

        <%!-- List View --%>
        <div :if={@view_mode == "list"}>
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

        <%!-- Calendar View --%>
        <div :if={@view_mode == "calendar"} class="p-4">
          <%!-- Calendar Header --%>
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold text-gray-900">
              {month_name(@calendar_month)} {@calendar_year}
            </h2>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="today"
                class="rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
              >
                Today
              </button>
              <div class="flex">
                <button
                  type="button"
                  phx-click="prev_month"
                  class="rounded-l-md bg-white p-1.5 text-gray-400 ring-1 ring-inset ring-gray-300 hover:text-gray-500 hover:bg-gray-50"
                >
                  <span class="hero-chevron-left h-5 w-5" />
                </button>
                <button
                  type="button"
                  phx-click="next_month"
                  class="-ml-px rounded-r-md bg-white p-1.5 text-gray-400 ring-1 ring-inset ring-gray-300 hover:text-gray-500 hover:bg-gray-50"
                >
                  <span class="hero-chevron-right h-5 w-5" />
                </button>
              </div>
            </div>
          </div>

          <%!-- Calendar Grid --%>
          <div class="border border-gray-200 rounded-lg overflow-hidden">
            <%!-- Day headers --%>
            <div class="grid grid-cols-7 bg-gray-50 border-b border-gray-200">
              <div :for={day <- ~w(Sun Mon Tue Wed Thu Fri Sat)} class="px-2 py-2 text-center text-xs font-medium text-gray-500">
                {day}
              </div>
            </div>

            <%!-- Calendar weeks --%>
            <div class="divide-y divide-gray-200">
              <div :for={week <- calendar_weeks(@calendar_year, @calendar_month)} class="grid grid-cols-7 divide-x divide-gray-200">
                <div
                  :for={date <- week}
                  class={"min-h-[100px] p-1 #{if in_current_month?(date, @calendar_year, @calendar_month), do: "bg-white", else: "bg-gray-50"} #{if is_today?(date), do: "bg-indigo-50"}"}
                >
                  <div class="flex items-center justify-between mb-1">
                    <span class={"text-xs font-medium #{if in_current_month?(date, @calendar_year, @calendar_month), do: "text-gray-900", else: "text-gray-400"} #{if is_today?(date), do: "text-indigo-600 font-bold"}"}>
                      {date.day}
                    </span>
                  </div>
                  <div class="space-y-1">
                    <div
                      :for={event <- Map.get(@calendar_events, date, []) |> Enum.take(3)}
                      class="group/event"
                    >
                      <.link
                        patch={~p"/events/#{event.id}/edit"}
                        class={"block px-1 py-0.5 text-xs rounded truncate #{type_bg_color(event.type)} hover:opacity-80"}
                      >
                        <span :if={!event.all_day} class="text-gray-500">{format_time(event.starts_at)}</span>
                        {event.title}
                      </.link>
                    </div>
                    <div
                      :if={length(Map.get(@calendar_events, date, [])) > 3}
                      class="text-xs text-gray-500 px-1"
                    >
                      +{length(Map.get(@calendar_events, date, [])) - 3} more
                    </div>
                  </div>
                </div>
              </div>
            </div>
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

  defp load_events(socket) do
    user = socket.assigns.current_user
    entity_filter = involvement_entity_id(socket.assigns)

    {events, meta} = Events.list_events(user.id,
      search: socket.assigns.search,
      type: socket.assigns.type_filter,
      sort: socket.assigns.sort,
      entity_id: entity_filter,
      time_filter: socket.assigns.time_filter,
      limit: @page_size
    )

    total_count = Events.count_events(user.id,
      search: socket.assigns.search,
      type: socket.assigns.type_filter,
      entity_id: entity_filter,
      time_filter: socket.assigns.time_filter
    )

    socket
    |> assign(:page, 0)
    |> assign(:has_more, meta.has_more)
    |> assign(:total_count, total_count)
    |> stream(:events, events, reset: true)
  end

  defp involvement_entity_id(%{involvement: "mine", self_entity_id: id}) when not is_nil(id), do: id
  defp involvement_entity_id(_), do: nil

  defp load_calendar_events(socket) do
    user = socket.assigns.current_user
    entity_filter = involvement_entity_id(socket.assigns)

    calendar_events = Events.list_events_for_month(
      user.id,
      socket.assigns.calendar_year,
      socket.assigns.calendar_month,
      entity_id: entity_filter,
      type: socket.assigns.type_filter
    )

    assign(socket, :calendar_events, calendar_events)
  end

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}

  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp month_name(month) do
    ~w(January February March April May June July August September October November December)
    |> Enum.at(month - 1)
  end

  defp calendar_weeks(year, month) do
    first_day = Date.new!(year, month, 1)

    # Go back to the start of the week (Sunday)
    days_since_sunday = Date.day_of_week(first_day, :sunday) - 1
    calendar_start = Date.add(first_day, -days_since_sunday)

    # Generate 6 weeks of dates (42 days total for consistent grid)
    Enum.map(0..5, fn week ->
      Enum.map(0..6, fn day ->
        Date.add(calendar_start, week * 7 + day)
      end)
    end)
  end

  defp in_current_month?(date, year, month) do
    date.year == year and date.month == month
  end

  defp is_today?(date) do
    date == Date.utc_today()
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M")
    |> String.trim_leading("0")
  end

  defp type_bg_color("birthday"), do: "bg-red-100 text-red-800"
  defp type_bg_color("anniversary"), do: "bg-indigo-100 text-indigo-800"
  defp type_bg_color("holiday"), do: "bg-red-100 text-red-800"
  defp type_bg_color("meeting"), do: "bg-blue-100 text-blue-800"
  defp type_bg_color("dinner"), do: "bg-yellow-100 text-yellow-800"
  defp type_bg_color("party"), do: "bg-green-100 text-green-800"
  defp type_bg_color("wedding"), do: "bg-indigo-100 text-indigo-800"
  defp type_bg_color("memorial"), do: "bg-gray-100 text-gray-800"
  defp type_bg_color(_), do: "bg-gray-100 text-gray-800"

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
