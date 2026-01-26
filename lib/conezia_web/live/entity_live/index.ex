defmodule ConeziaWeb.EntityLive.Index do
  @moduledoc """
  LiveView for listing and managing connections/entities.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Entities
  alias Conezia.Entities.{Entity, Relationship}

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    {entities, meta} = Entities.list_entities(user.id, limit: @page_size, sort: "name")
    entity_ids = Enum.map(entities, & &1.id)
    relationships = Entities.get_relationships_for_entities(user.id, entity_ids)
    total_count = Entities.count_entities(user.id)

    socket =
      socket
      |> assign(:page_title, "Connections")
      |> assign(:search, "")
      |> assign(:type_filter, nil)
      |> assign(:sort, "name")
      |> assign(:relationships, relationships)
      |> assign(:page, 0)
      |> assign(:has_more, meta.has_more)
      |> assign(:loading, false)
      |> assign(:total_count, total_count)
      |> stream(:entities, entities)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Connection")
    |> assign(:entity, %Entity{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Connections")
    |> assign(:entity, nil)
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    user = socket.assigns.current_user
    type = socket.assigns.type_filter
    sort = socket.assigns.sort

    {entities, meta} = Entities.list_entities(user.id, search: search, type: type, sort: sort, limit: @page_size)
    entity_ids = Enum.map(entities, & &1.id)
    relationships = Entities.get_relationships_for_entities(user.id, entity_ids)
    total_count = Entities.count_entities(user.id, search: search, type: type)

    socket =
      socket
      |> assign(:search, search)
      |> assign(:relationships, relationships)
      |> assign(:page, 0)
      |> assign(:has_more, meta.has_more)
      |> assign(:total_count, total_count)
      |> stream(:entities, entities, reset: true)

    {:noreply, socket}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    user = socket.assigns.current_user
    search = socket.assigns.search
    sort = socket.assigns.sort
    type = if type == "", do: nil, else: type

    {entities, meta} = Entities.list_entities(user.id, search: search, type: type, sort: sort, limit: @page_size)
    entity_ids = Enum.map(entities, & &1.id)
    relationships = Entities.get_relationships_for_entities(user.id, entity_ids)
    total_count = Entities.count_entities(user.id, search: search, type: type)

    socket =
      socket
      |> assign(:type_filter, type)
      |> assign(:relationships, relationships)
      |> assign(:page, 0)
      |> assign(:has_more, meta.has_more)
      |> assign(:total_count, total_count)
      |> stream(:entities, entities, reset: true)

    {:noreply, socket}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    user = socket.assigns.current_user
    search = socket.assigns.search
    type = socket.assigns.type_filter

    {entities, meta} = Entities.list_entities(user.id, search: search, type: type, sort: sort, limit: @page_size)
    entity_ids = Enum.map(entities, & &1.id)
    relationships = Entities.get_relationships_for_entities(user.id, entity_ids)

    socket =
      socket
      |> assign(:sort, sort)
      |> assign(:relationships, relationships)
      |> assign(:page, 0)
      |> assign(:has_more, meta.has_more)
      |> stream(:entities, entities, reset: true)

    {:noreply, socket}
  end

  def handle_event("load-more", _params, socket) do
    # Prevent duplicate loads
    if socket.assigns.loading or not socket.assigns.has_more do
      {:noreply, socket}
    else
      user = socket.assigns.current_user
      search = socket.assigns.search
      type = socket.assigns.type_filter
      sort = socket.assigns.sort
      next_page = socket.assigns.page + 1
      offset = next_page * @page_size

      socket = assign(socket, :loading, true)

      {entities, meta} = Entities.list_entities(user.id,
        search: search,
        type: type,
        sort: sort,
        limit: @page_size,
        offset: offset
      )

      entity_ids = Enum.map(entities, & &1.id)
      new_relationships = Entities.get_relationships_for_entities(user.id, entity_ids)
      relationships = Map.merge(socket.assigns.relationships, new_relationships)

      socket =
        socket
        |> assign(:page, next_page)
        |> assign(:has_more, meta.has_more)
        |> assign(:loading, false)
        |> assign(:relationships, relationships)
        |> stream(:entities, entities)

      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    entity = Entities.get_entity_for_user(id, user.id)

    case entity do
      nil ->
        {:noreply, put_flash(socket, :error, "Connection not found")}

      entity ->
        {:ok, _} = Entities.delete_entity(entity)

        {:noreply,
         socket
         |> stream_delete(:entities, entity)
         |> put_flash(:info, "Connection deleted successfully")}
    end
  end

  @impl true
  def handle_info({ConeziaWeb.EntityLive.FormComponent, {:saved, entity}}, socket) do
    user = socket.assigns.current_user
    relationship = Entities.get_relationship_for_entity(user.id, entity.id)
    relationships = Map.put(socket.assigns.relationships, entity.id, relationship)

    {:noreply,
     socket
     |> assign(:relationships, relationships)
     |> stream_insert(:entities, entity, at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Connections
        <:subtitle>Manage your relationships with people, organizations, and more</:subtitle>
        <:actions>
          <.link patch={~p"/connections/new"}>
            <.button>
              <span class="hero-plus -ml-0.5 mr-1.5 h-5 w-5" />
              Add Connection
            </.button>
          </.link>
        </:actions>
      </.header>

      <!-- Search and filters -->
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="flex items-center gap-4 flex-1">
          <form phx-change="search" phx-submit="search" class="flex-1 max-w-md">
            <div class="relative">
              <span class="hero-magnifying-glass absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-400" />
              <input
                type="text"
                name="search"
                value={@search}
                placeholder="Search connections..."
                phx-debounce="300"
                class="block w-full rounded-lg border-gray-300 pl-10 text-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
            </div>
          </form>
          <span class="text-sm text-gray-500 whitespace-nowrap">
            {format_count(@total_count)}
          </span>
        </div>

        <div class="flex gap-2">
          <form phx-change="sort">
            <select
              name="sort"
              class="block rounded-lg border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option value="name" selected={@sort == "name"}>Name (A-Z)</option>
              <option value="name_desc" selected={@sort == "name_desc"}>Name (Z-A)</option>
              <option value="last_interaction" selected={@sort == "last_interaction"}>Last Interaction</option>
              <option value="recent" selected={@sort == "recent"}>Recently Added</option>
              <option value="oldest" selected={@sort == "oldest"}>Oldest First</option>
            </select>
          </form>

          <form phx-change="filter_type">
            <select
              name="type"
              class="block rounded-lg border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option value="">All Types</option>
              <option value="person" selected={@type_filter == "person"}>People</option>
              <option value="organization" selected={@type_filter == "organization"}>Organizations</option>
            </select>
          </form>
        </div>
      </div>

      <!-- Entity list -->
      <div class="bg-white shadow ring-1 ring-gray-200 rounded-lg overflow-hidden">
        <ul id="entities" phx-update="stream" role="list" class="divide-y divide-gray-200">
          <li
            :for={{dom_id, entity} <- @streams.entities}
            id={dom_id}
            class="hover:bg-gray-50"
          >
            <div class="flex items-center px-4 py-4 sm:px-6">
              <.link navigate={~p"/connections/#{entity.id}"} class="flex min-w-0 flex-1 items-center">
                <div class="flex-shrink-0">
                  <.avatar name={entity.name} size={:lg} />
                </div>
                <div class="min-w-0 flex-1 px-4">
                  <div>
                    <p class="truncate text-sm font-medium text-indigo-600">{entity.name}</p>
                    <p class="mt-1 truncate text-sm text-gray-500">{entity.description || "No description"}</p>
                  </div>
                  <div class="mt-2 flex items-center gap-2 flex-wrap">
                    <.badge color={entity_type_color(entity.type)}>{entity.type || "person"}</.badge>
                    <.badge :if={relationship = @relationships[entity.id]} color={relationship_type_color(relationship.type)}>
                      {relationship_display_label(relationship)}
                    </.badge>
                    <.health_badge status={health_status(entity)} />
                    <%= for source <- get_sync_sources(entity) do %>
                      <.badge color={source_color(source)} class="text-xs">
                        <.icon name="hero-cloud-arrow-down" class="h-3 w-3 mr-0.5" />
                        {source_display_name(source)}
                      </.badge>
                    <% end %>
                  </div>
                </div>
              </.link>
              <div class="flex items-center gap-1 ml-4">
                <.link
                  patch={~p"/connections/#{entity.id}/edit"}
                  class="inline-flex items-center justify-center p-2 rounded-md border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 hover:text-indigo-600"
                  title="Edit"
                >
                  <.icon name="hero-pencil-square" class="h-4 w-4" />
                  <span class="sr-only">Edit</span>
                </.link>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={entity.id}
                  data-confirm="Are you sure you want to delete this connection?"
                  class="inline-flex items-center justify-center p-2 rounded-md border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 hover:text-red-600"
                  title="Delete"
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                  <span class="sr-only">Delete</span>
                </button>
                <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400 ml-2" />
              </div>
            </div>
          </li>
        </ul>

        <!-- Infinite scroll trigger -->
        <div
          :if={@has_more}
          id="infinite-scroll-trigger"
          phx-hook="InfiniteScroll"
          class="py-4 flex justify-center"
        >
          <div class="flex items-center gap-2 text-gray-500">
            <svg class="animate-spin h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <span>Loading more...</span>
          </div>
        </div>

        <div :if={@streams.entities.inserts == []} class="py-12">
          <.empty_state>
            <:icon><span class="hero-link h-12 w-12" /></:icon>
            <:title>No connections found</:title>
            <:description>
              {if @search != "" or @type_filter, do: "Try adjusting your search or filters.", else: "Get started by adding your first connection."}
            </:description>
            <:action :if={@search == "" and is_nil(@type_filter)}>
              <.link patch={~p"/connections/new"}>
                <.button>Add Connection</.button>
              </.link>
            </:action>
          </.empty_state>
        </div>
      </div>

      <.modal
        :if={@live_action == :new}
        id="entity-modal"
        show
        on_cancel={JS.patch(~p"/connections")}
      >
        <.live_component
          module={ConeziaWeb.EntityLive.FormComponent}
          id={:new}
          title="New Connection"
          action={@live_action}
          entity={@entity}
          relationship={nil}
          current_user={@current_user}
          patch={~p"/connections"}
        />
      </.modal>
    </div>
    """
  end

  defp entity_type_color("person"), do: :blue
  defp entity_type_color("organization"), do: :indigo
  defp entity_type_color(_), do: :gray

  defp health_status(%{last_interaction_at: last_interaction}) when not is_nil(last_interaction) do
    days_since = DateTime.diff(DateTime.utc_now(), last_interaction, :day)

    cond do
      days_since <= 30 -> :healthy
      days_since <= 90 -> :attention
      true -> :critical
    end
  end

  defp health_status(_), do: :unknown

  defp relationship_type_color("family"), do: :pink
  defp relationship_type_color("friend"), do: :green
  defp relationship_type_color("colleague"), do: :blue
  defp relationship_type_color("professional"), do: :indigo
  defp relationship_type_color("community"), do: :purple
  defp relationship_type_color("service"), do: :yellow
  defp relationship_type_color(_), do: :gray

  defp relationship_display_label(nil), do: "Connection"
  defp relationship_display_label(relationship) do
    Relationship.display_label(relationship)
  end

  defp get_sync_sources(entity) do
    metadata = entity.metadata || %{}
    sources = metadata["sources"] || []

    # Fallback to legacy source field if sources list is empty
    if Enum.empty?(sources) do
      case metadata["source"] do
        nil -> []
        source -> [source]
      end
    else
      sources
    end
  end

  defp source_display_name("google_contacts"), do: "Google"
  defp source_display_name("google_calendar"), do: "Calendar"
  defp source_display_name("gmail"), do: "Gmail"
  defp source_display_name("linkedin"), do: "LinkedIn"
  defp source_display_name("facebook"), do: "Facebook"
  defp source_display_name("icloud"), do: "iCloud"
  defp source_display_name("outlook"), do: "Outlook"
  defp source_display_name("csv"), do: "CSV"
  defp source_display_name("vcard"), do: "vCard"
  defp source_display_name(other), do: other

  defp source_color("google_contacts"), do: :blue
  defp source_color("google_calendar"), do: :green
  defp source_color("gmail"), do: :red
  defp source_color("linkedin"), do: :blue
  defp source_color("facebook"), do: :indigo
  defp source_color("icloud"), do: :gray
  defp source_color("outlook"), do: :blue
  defp source_color(_), do: :gray

  defp format_count(1), do: "1 connection"
  defp format_count(count), do: "#{count} connections"
end
