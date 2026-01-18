defmodule ConeziaWeb.EntityLive.Index do
  @moduledoc """
  LiveView for listing and managing connections/entities.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Entities
  alias Conezia.Entities.Entity

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Connections")
      |> assign(:search, "")
      |> assign(:type_filter, nil)
      |> stream(:entities, Entities.list_entities(user.id))

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

    entities = Entities.list_entities(user.id, search: search, type: type)

    socket =
      socket
      |> assign(:search, search)
      |> stream(:entities, entities, reset: true)

    {:noreply, socket}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    user = socket.assigns.current_user
    search = socket.assigns.search
    type = if type == "", do: nil, else: type

    entities = Entities.list_entities(user.id, search: search, type: type)

    socket =
      socket
      |> assign(:type_filter, type)
      |> stream(:entities, entities, reset: true)

    {:noreply, socket}
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
    {:noreply, stream_insert(socket, :entities, entity, at: 0)}
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

      <!-- Entity list -->
      <div class="bg-white shadow ring-1 ring-gray-200 rounded-lg overflow-hidden">
        <ul id="entities" phx-update="stream" role="list" class="divide-y divide-gray-200">
          <li
            :for={{dom_id, entity} <- @streams.entities}
            id={dom_id}
            class="hover:bg-gray-50"
          >
            <.link navigate={~p"/connections/#{entity.id}"} class="block">
              <div class="flex items-center px-4 py-4 sm:px-6">
                <div class="flex min-w-0 flex-1 items-center">
                  <div class="flex-shrink-0">
                    <.avatar name={entity.name} size={:lg} />
                  </div>
                  <div class="min-w-0 flex-1 px-4">
                    <div>
                      <p class="truncate text-sm font-medium text-indigo-600">{entity.name}</p>
                      <p class="mt-1 truncate text-sm text-gray-500">{entity.description || "No description"}</p>
                    </div>
                    <div class="mt-2 flex items-center gap-2">
                      <.badge color={entity_type_color(entity.type)}>{entity.type}</.badge>
                      <.health_badge status={health_status(entity)} />
                    </div>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <.link
                    patch={~p"/connections/#{entity.id}/edit"}
                    class="text-gray-400 hover:text-gray-500"
                  >
                    <span class="hero-pencil-square h-5 w-5" />
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={entity.id}
                    data-confirm="Are you sure you want to delete this connection?"
                    class="text-gray-400 hover:text-red-500"
                  >
                    <span class="hero-trash h-5 w-5" />
                  </button>
                  <span class="hero-chevron-right h-5 w-5 text-gray-400" />
                </div>
              </div>
            </.link>
          </li>
        </ul>

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

  defp health_status(%{health_score: score}) when is_number(score) do
    cond do
      score >= 70 -> :healthy
      score >= 40 -> :attention
      true -> :critical
    end
  end

  defp health_status(_), do: :unknown
end
