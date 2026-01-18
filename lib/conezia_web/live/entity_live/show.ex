defmodule ConeziaWeb.EntityLive.Show do
  @moduledoc """
  LiveView for viewing and editing a single connection/entity.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Entities
  alias Conezia.Entities.Relationship
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
        relationship = Entities.get_relationship_for_entity(user.id, entity.id)
        custom_fields = Entities.list_custom_fields(entity.id)

        socket =
          socket
          |> assign(:page_title, entity.name)
          |> assign(:entity, entity)
          |> assign(:relationship, relationship)
          |> assign(:custom_fields, custom_fields)
          |> assign(:interactions, list_interactions(entity.id, user.id))
          |> assign(:reminders, list_reminders(entity.id, user.id))
          |> assign(:editing_custom_field, nil)
          |> assign(:new_custom_field, nil)

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

  def handle_event("add_custom_field", _params, socket) do
    {:noreply, assign(socket, :new_custom_field, %{
      field_type: "text",
      category: "personal",
      name: "",
      value: ""
    })}
  end

  def handle_event("cancel_add_custom_field", _params, socket) do
    {:noreply, assign(socket, :new_custom_field, nil)}
  end

  def handle_event("save_custom_field", %{"custom_field" => params}, socket) do
    entity = socket.assigns.entity
    attrs = %{
      entity_id: entity.id,
      name: params["name"],
      key: normalize_key(params["name"]),
      field_type: params["field_type"],
      category: params["category"],
      is_recurring: params["is_recurring"] == "true"
    }
    |> put_field_value(params["field_type"], params["value"])

    case Entities.create_custom_field(attrs) do
      {:ok, _field} ->
        custom_fields = Entities.list_custom_fields(entity.id)
        {:noreply,
         socket
         |> assign(:custom_fields, custom_fields)
         |> assign(:new_custom_field, nil)
         |> put_flash(:info, "Custom field added")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add custom field")}
    end
  end

  def handle_event("delete_custom_field", %{"id" => id}, socket) do
    entity = socket.assigns.entity

    case Entities.get_custom_field(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Field not found")}

      field ->
        case Entities.delete_custom_field(field) do
          {:ok, _} ->
            custom_fields = Entities.list_custom_fields(entity.id)
            {:noreply,
             socket
             |> assign(:custom_fields, custom_fields)
             |> put_flash(:info, "Custom field deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete custom field")}
        end
    end
  end

  @impl true
  def handle_info({ConeziaWeb.EntityLive.FormComponent, {:saved, entity}}, socket) do
    user = socket.assigns.current_user
    relationship = Entities.get_relationship_for_entity(user.id, entity.id)

    {:noreply,
     socket
     |> assign(:entity, entity)
     |> assign(:relationship, relationship)
     |> assign(:page_title, entity.name)}
  end

  defp normalize_key(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp put_field_value(attrs, "date", value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(attrs, :date_value, date)
      _ -> attrs
    end
  end
  defp put_field_value(attrs, "number", value) when is_binary(value) and value != "" do
    case Decimal.parse(value) do
      {decimal, _} -> Map.put(attrs, :number_value, decimal)
      _ -> attrs
    end
  end
  defp put_field_value(attrs, "boolean", value), do: Map.put(attrs, :boolean_value, value == "true")
  defp put_field_value(attrs, _type, value), do: Map.put(attrs, :value, value)

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
              <.badge :if={@relationship} color={relationship_type_color(@relationship.type)}>
                {relationship_display_label(@relationship)}
              </.badge>
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
              <:item :if={@relationship} title="Relationship">
                {relationship_display_label(@relationship)}
              </:item>
              <:item :if={@entity.last_interaction_at} title="Last Interaction">
                {format_datetime(@entity.last_interaction_at)}
              </:item>
              <:item title="Created">{format_datetime(@entity.inserted_at)}</:item>
            </.list>
          </.card>

          <!-- Custom Fields -->
          <.card>
            <:header>
              <div class="flex items-center justify-between">
                <span>Custom Information</span>
                <button
                  :if={is_nil(@new_custom_field)}
                  phx-click="add_custom_field"
                  class="text-sm font-medium text-indigo-600 hover:text-indigo-500"
                >
                  Add Field →
                </button>
              </div>
            </:header>

            <!-- Add new custom field form -->
            <div :if={@new_custom_field} class="mb-4 p-4 bg-gray-50 rounded-lg">
              <form phx-submit="save_custom_field" class="space-y-3">
                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <label class="block text-sm font-medium text-gray-700">Field Name</label>
                    <input
                      type="text"
                      name="custom_field[name]"
                      placeholder="e.g., Birthday, Company"
                      required
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700">Type</label>
                    <select
                      name="custom_field[field_type]"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    >
                      <option value="text">Text</option>
                      <option value="date">Date</option>
                      <option value="number">Number</option>
                      <option value="boolean">Yes/No</option>
                      <option value="url">URL</option>
                      <option value="email">Email</option>
                      <option value="phone">Phone</option>
                    </select>
                  </div>
                </div>
                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <label class="block text-sm font-medium text-gray-700">Category</label>
                    <select
                      name="custom_field[category]"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    >
                      <option value="important_dates">Important Dates</option>
                      <option value="preferences">Preferences</option>
                      <option value="work">Work</option>
                      <option value="personal">Personal</option>
                      <option value="social">Social</option>
                      <option value="other">Other</option>
                    </select>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700">Value</label>
                    <input
                      type="text"
                      name="custom_field[value]"
                      placeholder="Enter value"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    />
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    name="custom_field[is_recurring]"
                    value="true"
                    id="is_recurring"
                    class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                  />
                  <label for="is_recurring" class="text-sm text-gray-600">
                    Recurring (for dates like birthdays)
                  </label>
                </div>
                <div class="flex gap-2 justify-end">
                  <button
                    type="button"
                    phx-click="cancel_add_custom_field"
                    class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
                  >
                    Save
                  </button>
                </div>
              </form>
            </div>

            <div :if={@custom_fields == []} class="py-8">
              <.empty_state>
                <:icon><span class="hero-document-text h-10 w-10" /></:icon>
                <:title>No custom information</:title>
                <:description>Add important dates, preferences, or other details about this connection.</:description>
              </.empty_state>
            </div>

            <div :if={@custom_fields != []}>
              <%= for {category, fields} <- group_custom_fields(@custom_fields) do %>
                <div class="mb-4">
                  <h4 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                    {humanize_type(category)}
                  </h4>
                  <dl class="divide-y divide-gray-200">
                    <div :for={field <- fields} class="py-2 flex items-center justify-between">
                      <dt class="text-sm font-medium text-gray-500">{field.name}</dt>
                      <dd class="flex items-center gap-2">
                        <span class="text-sm text-gray-900">{format_field_value(field)}</span>
                        <span :if={field.is_recurring} class="text-xs text-gray-400">(recurring)</span>
                        <button
                          phx-click="delete_custom_field"
                          phx-value-id={field.id}
                          data-confirm="Delete this field?"
                          class="text-gray-400 hover:text-red-500"
                        >
                          <span class="hero-x-mark h-4 w-4" />
                        </button>
                      </dd>
                    </div>
                  </dl>
                </div>
              <% end %>
            </div>
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
          relationship={@relationship}
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

  defp health_status(%{last_interaction_at: last_interaction}) when not is_nil(last_interaction) do
    days_since = DateTime.diff(DateTime.utc_now(), last_interaction, :day)

    cond do
      days_since <= 30 -> :healthy
      days_since <= 90 -> :attention
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

  defp group_custom_fields(fields) do
    fields
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {category, _} -> category_sort_order(category) end)
  end

  defp category_sort_order("important_dates"), do: 0
  defp category_sort_order("work"), do: 1
  defp category_sort_order("personal"), do: 2
  defp category_sort_order("preferences"), do: 3
  defp category_sort_order("social"), do: 4
  defp category_sort_order(_), do: 5

  defp format_field_value(%{field_type: "date", date_value: date}) when not is_nil(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end
  defp format_field_value(%{field_type: "boolean", boolean_value: true}), do: "Yes"
  defp format_field_value(%{field_type: "boolean", boolean_value: false}), do: "No"
  defp format_field_value(%{field_type: "number", number_value: num}) when not is_nil(num) do
    Decimal.to_string(num)
  end
  defp format_field_value(%{value: value}) when not is_nil(value), do: value
  defp format_field_value(_), do: "-"
end
