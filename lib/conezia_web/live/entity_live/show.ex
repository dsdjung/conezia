defmodule ConeziaWeb.EntityLive.Show do
  @moduledoc """
  LiveView for viewing and editing a single connection/entity.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Entities
  alias Conezia.Entities.{Relationship, EntityRelationship}
  alias Conezia.Interactions
  alias Conezia.Reminders
  alias Conezia.Communications
  alias Conezia.Integrations.Gmail

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
        entity_relationships = Entities.list_entity_relationships_for_entity(entity.id, user.id)
        active_identifiers = Entities.list_active_identifiers_for_entity(entity.id)
        archived_identifiers = Entities.list_archived_identifiers_for_entity(entity.id)
        last_communication = Communications.get_last_communication_for_entity(entity.id)
        last_event = Interactions.get_last_event_for_entity(entity.id, user.id)

        # Fetch last Gmail email on-demand if we have email identifiers
        last_gmail_email = fetch_last_gmail_email(user.id, active_identifiers)

        socket =
          socket
          |> assign(:page_title, entity.name)
          |> assign(:entity, entity)
          |> assign(:relationship, relationship)
          |> assign(:custom_fields, custom_fields)
          |> assign(:entity_relationships, entity_relationships)
          |> assign(:identifiers, active_identifiers)
          |> assign(:archived_identifiers, archived_identifiers)
          |> assign(:show_archived_identifiers, false)
          |> assign(:interactions, list_interactions(entity.id, user.id))
          |> assign(:reminders, list_reminders(entity.id, user.id))
          |> assign(:last_communication, last_communication)
          |> assign(:last_event, last_event)
          |> assign(:last_gmail_email, last_gmail_email)
          |> assign(:editing_custom_field, nil)
          |> assign(:new_custom_field, nil)
          |> assign(:adding_entity_relationship, false)
          |> assign(:available_entities, [])
          |> assign(:merging, false)
          |> assign(:merge_candidates, [])
          |> assign(:merge_search, "")
          |> assign(:filtered_merge_candidates, [])
          |> assign(:adding_identifier, nil)
          |> assign(:editing_identifier, nil)

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

  def handle_event("custom_field_type_changed", %{"custom_field" => %{"field_type" => field_type}}, socket) do
    new_custom_field = Map.put(socket.assigns.new_custom_field, :field_type, field_type)
    {:noreply, assign(socket, :new_custom_field, new_custom_field)}
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

  # Entity relationship events
  def handle_event("add_entity_relationship", _params, socket) do
    user = socket.assigns.current_user
    entity = socket.assigns.entity

    # Get other entities to choose from (exclude current entity)
    {all_entities, _meta} = Entities.list_entities(user.id)
    available_entities = Enum.reject(all_entities, fn e -> e.id == entity.id end)

    {:noreply,
     socket
     |> assign(:adding_entity_relationship, true)
     |> assign(:available_entities, available_entities)}
  end

  def handle_event("cancel_add_entity_relationship", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding_entity_relationship, false)
     |> assign(:available_entities, [])}
  end

  def handle_event("save_entity_relationship", %{"entity_relationship" => params}, socket) do
    user = socket.assigns.current_user
    entity = socket.assigns.entity

    attrs = %{
      user_id: user.id,
      source_entity_id: entity.id,
      target_entity_id: blank_to_nil(params["target_entity_id"]),
      type: blank_to_nil(params["type"]),
      subtype: blank_to_nil(params["subtype"]),
      custom_label: blank_to_nil(params["custom_label"]),
      notes: blank_to_nil(params["notes"])
    }

    case Entities.create_entity_relationship(attrs) do
      {:ok, _rel} ->
        entity_relationships = Entities.list_entity_relationships_for_entity(entity.id, user.id)
        {:noreply,
         socket
         |> assign(:entity_relationships, entity_relationships)
         |> assign(:adding_entity_relationship, false)
         |> assign(:available_entities, [])
         |> put_flash(:info, "Connection relationship added")}

      {:error, changeset} ->
        error_msg = changeset_error_message(changeset)
        {:noreply, put_flash(socket, :error, "Failed to add relationship: #{error_msg}")}
    end
  end

  def handle_event("delete_entity_relationship", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    entity = socket.assigns.entity

    case Entities.get_entity_relationship_for_user(id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Relationship not found")}

      rel ->
        case Entities.delete_entity_relationship(rel) do
          {:ok, _} ->
            entity_relationships = Entities.list_entity_relationships_for_entity(entity.id, user.id)
            {:noreply,
             socket
             |> assign(:entity_relationships, entity_relationships)
             |> put_flash(:info, "Connection relationship removed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove relationship")}
        end
    end
  end

  # Merge connection events
  def handle_event("start_merge", _params, socket) do
    user = socket.assigns.current_user
    entity = socket.assigns.entity

    # Get ALL entities of the same type to merge with (no pagination limit)
    # Using a high limit to fetch all candidates for the merge picker
    {all_entities, _meta} = Entities.list_entities(user.id, type: entity.type, limit: 10_000)
    merge_candidates = Enum.reject(all_entities, fn e -> e.id == entity.id end)

    {:noreply,
     socket
     |> assign(:merging, true)
     |> assign(:merge_candidates, merge_candidates)
     |> assign(:merge_search, "")
     |> assign(:filtered_merge_candidates, merge_candidates)}
  end

  def handle_event("cancel_merge", _params, socket) do
    {:noreply,
     socket
     |> assign(:merging, false)
     |> assign(:merge_candidates, [])
     |> assign(:merge_search, "")
     |> assign(:filtered_merge_candidates, [])}
  end

  def handle_event("merge_search", %{"value" => search_term}, socket) do
    candidates = socket.assigns.merge_candidates
    search_term = String.trim(search_term)

    filtered =
      if search_term == "" do
        candidates
      else
        search_lower = String.downcase(search_term)

        Enum.filter(candidates, fn candidate ->
          name_match = candidate.name && String.contains?(String.downcase(candidate.name), search_lower)
          desc_match = candidate.description && String.contains?(String.downcase(candidate.description), search_lower)
          name_match || desc_match
        end)
      end

    {:noreply,
     socket
     |> assign(:merge_search, search_term)
     |> assign(:filtered_merge_candidates, filtered)}
  end

  def handle_event("merge_into", %{"target_id" => target_id}, socket) do
    user = socket.assigns.current_user
    source_entity = socket.assigns.entity

    case Entities.merge_entities(source_entity.id, target_id, user.id) do
      {:ok, {target_entity, summary}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Merged successfully! #{summary.identifiers_added} identifiers, #{summary.interactions_transferred} interactions transferred.")
         |> push_navigate(to: ~p"/connections/#{target_entity.id}")}

      {:error, :same_entity} ->
        {:noreply, put_flash(socket, :error, "Cannot merge an entity with itself")}

      {:error, :type_mismatch} ->
        {:noreply, put_flash(socket, :error, "Cannot merge entities of different types")}

      {:error, {:not_found, _}} ->
        {:noreply, put_flash(socket, :error, "Entity not found")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Merge failed: #{inspect(reason)}")}
    end
  end

  # Identifier management events
  def handle_event("add_identifier", %{"type" => type}, socket) do
    {:noreply, assign(socket, :adding_identifier, type)}
  end

  def handle_event("cancel_add_identifier", _params, socket) do
    {:noreply, assign(socket, :adding_identifier, nil)}
  end

  def handle_event("save_identifier", %{"identifier" => params}, socket) do
    entity = socket.assigns.entity
    type = socket.assigns.adding_identifier

    # Check if this is the first identifier of this type (make it primary)
    has_type = Entities.has_identifier_type?(entity.id, type)

    attrs = %{
      "entity_id" => entity.id,
      "type" => type,
      "value" => params["value"],
      "label" => params["label"],
      "is_primary" => !has_type
    }

    case Entities.create_identifier(attrs) do
      {:ok, _identifier} ->
        identifiers = Entities.list_active_identifiers_for_entity(entity.id)

        {:noreply,
         socket
         |> assign(:identifiers, identifiers)
         |> assign(:adding_identifier, nil)
         |> put_flash(:info, "#{String.capitalize(type)} added successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add #{type}")}
    end
  end

  def handle_event("edit_identifier", %{"id" => id}, socket) do
    identifier = Entities.get_identifier(id)
    {:noreply, assign(socket, :editing_identifier, identifier)}
  end

  def handle_event("cancel_edit_identifier", _params, socket) do
    {:noreply, assign(socket, :editing_identifier, nil)}
  end

  def handle_event("update_identifier", %{"identifier" => params}, socket) do
    identifier = socket.assigns.editing_identifier

    case Entities.update_identifier(identifier, params) do
      {:ok, _updated} ->
        identifiers = Entities.list_active_identifiers_for_entity(socket.assigns.entity.id)

        {:noreply,
         socket
         |> assign(:identifiers, identifiers)
         |> assign(:editing_identifier, nil)
         |> put_flash(:info, "Updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update")}
    end
  end

  def handle_event("delete_identifier", %{"id" => id}, socket) do
    identifier = Entities.get_identifier(id)

    case Entities.delete_identifier(identifier) do
      {:ok, _} ->
        active_identifiers = Entities.list_active_identifiers_for_entity(socket.assigns.entity.id)
        archived_identifiers = Entities.list_archived_identifiers_for_entity(socket.assigns.entity.id)

        {:noreply,
         socket
         |> assign(:identifiers, active_identifiers)
         |> assign(:archived_identifiers, archived_identifiers)
         |> put_flash(:info, "Removed successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove")}
    end
  end

  def handle_event("set_primary_identifier", %{"id" => id}, socket) do
    identifier = Entities.get_identifier(id)
    entity_id = socket.assigns.entity.id

    # First, unset any existing primary identifier of this type
    socket.assigns.identifiers
    |> Enum.filter(&(&1.type == identifier.type && &1.is_primary))
    |> Enum.each(fn existing_primary ->
      Entities.update_identifier(existing_primary, %{"is_primary" => false})
    end)

    # Set this one as primary
    case Entities.update_identifier(identifier, %{"is_primary" => true}) do
      {:ok, _} ->
        identifiers = Entities.list_active_identifiers_for_entity(entity_id)

        {:noreply,
         socket
         |> assign(:identifiers, identifiers)
         |> put_flash(:info, "Set as primary")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to set as primary")}
    end
  end

  def handle_event("archive_identifier", %{"id" => id}, socket) do
    identifier = Entities.get_identifier(id)
    entity_id = socket.assigns.entity.id

    case Entities.archive_identifier(identifier) do
      {:ok, _} ->
        active_identifiers = Entities.list_active_identifiers_for_entity(entity_id)
        archived_identifiers = Entities.list_archived_identifiers_for_entity(entity_id)

        {:noreply,
         socket
         |> assign(:identifiers, active_identifiers)
         |> assign(:archived_identifiers, archived_identifiers)
         |> put_flash(:info, "Moved to archived")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to archive")}
    end
  end

  def handle_event("unarchive_identifier", %{"id" => id}, socket) do
    identifier = Entities.get_identifier(id)
    entity_id = socket.assigns.entity.id

    case Entities.unarchive_identifier(identifier) do
      {:ok, _} ->
        active_identifiers = Entities.list_active_identifiers_for_entity(entity_id)
        archived_identifiers = Entities.list_archived_identifiers_for_entity(entity_id)

        {:noreply,
         socket
         |> assign(:identifiers, active_identifiers)
         |> assign(:archived_identifiers, archived_identifiers)
         |> put_flash(:info, "Restored from archived")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to restore")}
    end
  end

  def handle_event("toggle_archived_identifiers", _params, socket) do
    {:noreply, assign(socket, :show_archived_identifiers, !socket.assigns.show_archived_identifiers)}
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
            <div class="mt-1 flex items-center gap-2 flex-wrap">
              <.badge color={entity_type_color(@entity.type)}>{@entity.type || "person"}</.badge>
              <.badge :if={@relationship} color={relationship_type_color(@relationship.type)}>
                {relationship_display_label(@relationship)}
              </.badge>
              <.health_badge status={health_status(@entity)} />
              <%= for source <- get_sync_sources(@entity) do %>
                <.badge color={source_color(source)} class="text-xs">
                  <.icon name="hero-cloud-arrow-down" class="h-3 w-3 mr-0.5" />
                  {source_display_name(source)}
                </.badge>
              <% end %>
            </div>
          </div>
        </div>
        <div class="mt-4 flex items-center gap-2 md:mt-0">
          <.link patch={~p"/connections/#{@entity.id}/edit"}>
            <.button class="inline-flex items-center !bg-white !text-gray-700 ring-1 ring-gray-300 hover:!bg-gray-50">
              <.icon name="hero-pencil-square" class="mr-1.5 h-5 w-5" />
              Edit
            </.button>
          </.link>
          <.button
            phx-click="start_merge"
            class="inline-flex items-center !bg-white !text-gray-700 ring-1 ring-gray-300 hover:!bg-gray-50"
          >
            <.icon name="hero-arrows-pointing-in" class="mr-1.5 h-5 w-5" />
            Merge
          </.button>
          <.button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this connection? This action cannot be undone."
            class="inline-flex items-center !bg-red-600 hover:!bg-red-700"
          >
            <.icon name="hero-trash" class="mr-1.5 h-5 w-5" />
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
              <:item title="Type">{String.capitalize(@entity.type || "person")}</:item>
              <:item :if={@relationship} title="Relationship">
                {relationship_display_label(@relationship)}
              </:item>
              <:item :if={@entity.last_interaction_at} title="Last Interaction">
                {format_datetime(@entity.last_interaction_at)}
              </:item>
              <:item title="Created">{format_datetime(@entity.inserted_at)}</:item>
            </.list>
          </.card>

          <!-- Contact Information (Emails, Phones) -->
          <.card>
            <:header>
              <div class="flex items-center justify-between">
                <span>Contact Information</span>
                <div class="flex gap-2">
                  <button
                    phx-click="add_identifier"
                    phx-value-type="email"
                    class="text-xs font-medium text-indigo-600 hover:text-indigo-500"
                  >
                    + Email
                  </button>
                  <button
                    phx-click="add_identifier"
                    phx-value-type="phone"
                    class="text-xs font-medium text-indigo-600 hover:text-indigo-500"
                  >
                    + Phone
                  </button>
                </div>
              </div>
            </:header>
            <div class="space-y-4">
              <!-- Add identifier form -->
              <div :if={@adding_identifier} class="bg-gray-50 rounded-lg p-3 border border-gray-200">
                <form phx-submit="save_identifier" class="space-y-3">
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">
                      {String.capitalize(@adding_identifier)}
                    </label>
                    <input
                      type={if @adding_identifier == "email", do: "email", else: "text"}
                      name="identifier[value]"
                      required
                      placeholder={identifier_placeholder(@adding_identifier)}
                      class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Label (optional)</label>
                    <input
                      type="text"
                      name="identifier[label]"
                      placeholder="e.g., Work, Personal, Home"
                      class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
                    />
                  </div>
                  <div class="flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="cancel_add_identifier"
                      class="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-800"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      class="px-3 py-1.5 text-sm bg-indigo-600 text-white rounded-md hover:bg-indigo-700"
                    >
                      Add
                    </button>
                  </div>
                </form>
              </div>

              <!-- Edit identifier form -->
              <div :if={@editing_identifier} class="bg-gray-50 rounded-lg p-3 border border-gray-200">
                <form phx-submit="update_identifier" class="space-y-3">
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">
                      {String.capitalize(@editing_identifier.type)}
                    </label>
                    <input
                      type={if @editing_identifier.type == "email", do: "email", else: "text"}
                      name="identifier[value]"
                      value={@editing_identifier.value}
                      required
                      class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Label (optional)</label>
                    <input
                      type="text"
                      name="identifier[label]"
                      value={@editing_identifier.label}
                      placeholder="e.g., Work, Personal, Home"
                      class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
                    />
                  </div>
                  <div class="flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="cancel_edit_identifier"
                      class="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-800"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      class="px-3 py-1.5 text-sm bg-indigo-600 text-white rounded-md hover:bg-indigo-700"
                    >
                      Save
                    </button>
                  </div>
                </form>
              </div>

              <!-- Emails -->
              <% emails = Enum.filter(@identifiers, & &1.type == "email") %>
              <div :if={emails != [] && !@editing_identifier}>
                <h4 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Email</h4>
                <ul class="space-y-2">
                  <li :for={email <- emails} class="group flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <.icon name="hero-envelope" class="h-4 w-4 text-gray-400" />
                      <a
                        href={"mailto:#{email.value}"}
                        class="text-sm text-indigo-600 hover:text-indigo-500"
                      >
                        {email.value}
                      </a>
                      <span :if={email.label} class="text-xs text-gray-500">({email.label})</span>
                      <.badge :if={email.is_primary} color={:green} class="text-xs">Primary</.badge>
                    </div>
                    <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                      <button
                        :if={!email.is_primary}
                        phx-click="set_primary_identifier"
                        phx-value-id={email.id}
                        title="Set as primary"
                        class="p-1 text-gray-400 hover:text-indigo-600"
                      >
                        <.icon name="hero-star" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="edit_identifier"
                        phx-value-id={email.id}
                        title="Edit"
                        class="p-1 text-gray-400 hover:text-indigo-600"
                      >
                        <.icon name="hero-pencil" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="archive_identifier"
                        phx-value-id={email.id}
                        title="Archive (mark as old)"
                        class="p-1 text-gray-400 hover:text-amber-600"
                      >
                        <.icon name="hero-archive-box" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="delete_identifier"
                        phx-value-id={email.id}
                        data-confirm="Remove this email address?"
                        title="Remove"
                        class="p-1 text-gray-400 hover:text-red-600"
                      >
                        <.icon name="hero-trash" class="h-4 w-4" />
                      </button>
                    </div>
                  </li>
                </ul>
              </div>

              <!-- Phones -->
              <% phones = Enum.filter(@identifiers, & &1.type == "phone") %>
              <div :if={phones != [] && !@editing_identifier}>
                <h4 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Phone</h4>
                <ul class="space-y-2">
                  <li :for={phone <- phones} class="group flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <.icon name="hero-phone" class="h-4 w-4 text-gray-400" />
                      <a
                        href={"tel:#{phone.value}"}
                        class="text-sm text-indigo-600 hover:text-indigo-500"
                      >
                        {phone.value}
                      </a>
                      <span :if={phone.label} class="text-xs text-gray-500">({phone.label})</span>
                      <.badge :if={phone.is_primary} color={:green} class="text-xs">Primary</.badge>
                    </div>
                    <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                      <button
                        :if={!phone.is_primary}
                        phx-click="set_primary_identifier"
                        phx-value-id={phone.id}
                        title="Set as primary"
                        class="p-1 text-gray-400 hover:text-indigo-600"
                      >
                        <.icon name="hero-star" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="edit_identifier"
                        phx-value-id={phone.id}
                        title="Edit"
                        class="p-1 text-gray-400 hover:text-indigo-600"
                      >
                        <.icon name="hero-pencil" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="archive_identifier"
                        phx-value-id={phone.id}
                        title="Archive (mark as old)"
                        class="p-1 text-gray-400 hover:text-amber-600"
                      >
                        <.icon name="hero-archive-box" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="delete_identifier"
                        phx-value-id={phone.id}
                        data-confirm="Remove this phone number?"
                        title="Remove"
                        class="p-1 text-gray-400 hover:text-red-600"
                      >
                        <.icon name="hero-trash" class="h-4 w-4" />
                      </button>
                    </div>
                  </li>
                </ul>
              </div>

              <!-- Other identifiers -->
              <% others = Enum.reject(@identifiers, & &1.type in ["email", "phone"]) %>
              <div :if={others != [] && !@editing_identifier}>
                <h4 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Other</h4>
                <ul class="space-y-2">
                  <li :for={identifier <- others} class="group flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <.icon name="hero-identification" class="h-4 w-4 text-gray-400" />
                      <span class="text-xs text-gray-500">{identifier.type}:</span>
                      <span class="text-sm text-gray-900">{identifier.value}</span>
                      <span :if={identifier.label} class="text-xs text-gray-500">({identifier.label})</span>
                      <.badge :if={identifier.is_primary} color={:green} class="text-xs">Primary</.badge>
                    </div>
                    <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                      <button
                        phx-click="edit_identifier"
                        phx-value-id={identifier.id}
                        title="Edit"
                        class="p-1 text-gray-400 hover:text-indigo-600"
                      >
                        <.icon name="hero-pencil" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="archive_identifier"
                        phx-value-id={identifier.id}
                        title="Archive (mark as old)"
                        class="p-1 text-gray-400 hover:text-amber-600"
                      >
                        <.icon name="hero-archive-box" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="delete_identifier"
                        phx-value-id={identifier.id}
                        data-confirm="Remove this identifier?"
                        title="Remove"
                        class="p-1 text-gray-400 hover:text-red-600"
                      >
                        <.icon name="hero-trash" class="h-4 w-4" />
                      </button>
                    </div>
                  </li>
                </ul>
              </div>

              <!-- Empty state -->
              <p :if={@identifiers == [] && !@adding_identifier && @archived_identifiers == []} class="text-sm text-gray-500 text-center py-4">
                No contact information yet. Add an email or phone number above.
              </p>

              <!-- Archived identifiers section -->
              <div :if={@archived_identifiers != []} class="mt-4 pt-4 border-t border-gray-200">
                <button
                  phx-click="toggle_archived_identifiers"
                  class="flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700"
                >
                  <.icon
                    name={if @show_archived_identifiers, do: "hero-chevron-down", else: "hero-chevron-right"}
                    class="h-4 w-4"
                  />
                  <.icon name="hero-archive-box" class="h-4 w-4" />
                  <span>Archived ({length(@archived_identifiers)})</span>
                </button>

                <div :if={@show_archived_identifiers} class="mt-3 space-y-3 pl-6">
                  <!-- Archived Emails -->
                  <% archived_emails = Enum.filter(@archived_identifiers, & &1.type == "email") %>
                  <div :if={archived_emails != []}>
                    <h5 class="text-xs font-medium text-gray-400 mb-1">Emails</h5>
                    <ul class="space-y-1">
                      <li :for={email <- archived_emails} class="group flex items-center justify-between text-gray-400">
                        <div class="flex items-center gap-2">
                          <.icon name="hero-envelope" class="h-4 w-4" />
                          <span class="text-sm line-through">{email.value}</span>
                          <span :if={email.label} class="text-xs">({email.label})</span>
                        </div>
                        <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            phx-click="unarchive_identifier"
                            phx-value-id={email.id}
                            title="Restore"
                            class="p-1 text-gray-400 hover:text-green-600"
                          >
                            <.icon name="hero-arrow-uturn-left" class="h-4 w-4" />
                          </button>
                          <button
                            phx-click="delete_identifier"
                            phx-value-id={email.id}
                            data-confirm="Permanently delete this email?"
                            title="Delete permanently"
                            class="p-1 text-gray-400 hover:text-red-600"
                          >
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </div>
                      </li>
                    </ul>
                  </div>

                  <!-- Archived Phones -->
                  <% archived_phones = Enum.filter(@archived_identifiers, & &1.type == "phone") %>
                  <div :if={archived_phones != []}>
                    <h5 class="text-xs font-medium text-gray-400 mb-1">Phones</h5>
                    <ul class="space-y-1">
                      <li :for={phone <- archived_phones} class="group flex items-center justify-between text-gray-400">
                        <div class="flex items-center gap-2">
                          <.icon name="hero-phone" class="h-4 w-4" />
                          <span class="text-sm line-through">{phone.value}</span>
                          <span :if={phone.label} class="text-xs">({phone.label})</span>
                        </div>
                        <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            phx-click="unarchive_identifier"
                            phx-value-id={phone.id}
                            title="Restore"
                            class="p-1 text-gray-400 hover:text-green-600"
                          >
                            <.icon name="hero-arrow-uturn-left" class="h-4 w-4" />
                          </button>
                          <button
                            phx-click="delete_identifier"
                            phx-value-id={phone.id}
                            data-confirm="Permanently delete this phone number?"
                            title="Delete permanently"
                            class="p-1 text-gray-400 hover:text-red-600"
                          >
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </div>
                      </li>
                    </ul>
                  </div>

                  <!-- Archived Others -->
                  <% archived_others = Enum.reject(@archived_identifiers, & &1.type in ["email", "phone"]) %>
                  <div :if={archived_others != []}>
                    <h5 class="text-xs font-medium text-gray-400 mb-1">Other</h5>
                    <ul class="space-y-1">
                      <li :for={identifier <- archived_others} class="group flex items-center justify-between text-gray-400">
                        <div class="flex items-center gap-2">
                          <.icon name="hero-identification" class="h-4 w-4" />
                          <span class="text-xs">{identifier.type}:</span>
                          <span class="text-sm line-through">{identifier.value}</span>
                          <span :if={identifier.label} class="text-xs">({identifier.label})</span>
                        </div>
                        <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            phx-click="unarchive_identifier"
                            phx-value-id={identifier.id}
                            title="Restore"
                            class="p-1 text-gray-400 hover:text-green-600"
                          >
                            <.icon name="hero-arrow-uturn-left" class="h-4 w-4" />
                          </button>
                          <button
                            phx-click="delete_identifier"
                            phx-value-id={identifier.id}
                            data-confirm="Permanently delete this?"
                            title="Delete permanently"
                            class="p-1 text-gray-400 hover:text-red-600"
                          >
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </div>
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          </.card>

          <!-- Related Connections (Entity-to-Entity Relationships) -->
          <.card>
            <:header>
              <div class="flex items-center justify-between">
                <span>Related Connections</span>
                <button
                  :if={!@adding_entity_relationship}
                  phx-click="add_entity_relationship"
                  class="text-sm font-medium text-indigo-600 hover:text-indigo-500"
                >
                  Add Relationship →
                </button>
              </div>
            </:header>

            <!-- Add new entity relationship form -->
            <div :if={@adding_entity_relationship} class="mb-4 p-4 bg-gray-50 rounded-lg">
              <form phx-submit="save_entity_relationship" class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700">Related Connection</label>
                  <select
                    name="entity_relationship[target_entity_id]"
                    required
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  >
                    <option value="">Select a connection...</option>
                    <option :for={entity <- @available_entities} value={entity.id}>
                      {entity.name}
                    </option>
                  </select>
                </div>
                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <label class="block text-sm font-medium text-gray-700">
                      They are {@entity.name}'s...
                    </label>
                    <select
                      name="entity_relationship[type]"
                      id="entity_rel_type"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    >
                      <option value="">Select type...</option>
                      <option value="family">Family</option>
                      <option value="friend">Friend</option>
                      <option value="colleague">Colleague</option>
                      <option value="professional">Professional</option>
                      <option value="community">Community</option>
                      <option value="other">Other</option>
                    </select>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700">Specific relationship</label>
                    <select
                      name="entity_relationship[subtype]"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    >
                      <option value="">Select subtype...</option>
                      <!-- Family subtypes -->
                      <optgroup label="Family">
                        <option value="spouse">Spouse</option>
                        <option value="parent">Parent</option>
                        <option value="child">Child</option>
                        <option value="older_sibling">Older Sibling</option>
                        <option value="younger_sibling">Younger Sibling</option>
                        <option value="grandparent">Grandparent</option>
                        <option value="grandchild">Grandchild</option>
                        <option value="aunt_uncle">Aunt/Uncle</option>
                        <option value="niece_nephew">Niece/Nephew</option>
                      </optgroup>
                      <!-- Friend subtypes -->
                      <optgroup label="Friends">
                        <option value="friend">Friend</option>
                        <option value="classmate">Classmate</option>
                        <option value="neighbor">Neighbor</option>
                        <option value="colleague">Colleague</option>
                      </optgroup>
                      <!-- Professional subtypes -->
                      <optgroup label="Professional">
                        <option value="employer">Employer</option>
                        <option value="employee">Employee</option>
                        <option value="manager">Manager</option>
                        <option value="direct_report">Direct Report</option>
                        <option value="mentor">Mentor</option>
                        <option value="mentee">Mentee</option>
                        <option value="client">Client</option>
                        <option value="service_provider">Service Provider</option>
                      </optgroup>
                    </select>
                  </div>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700">Custom Label (optional)</label>
                  <input
                    type="text"
                    name="entity_relationship[custom_label]"
                    placeholder="e.g., Best friend from college"
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700">Notes (optional)</label>
                  <textarea
                    name="entity_relationship[notes]"
                    rows="2"
                    placeholder="Add any notes about this relationship..."
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  ></textarea>
                </div>
                <div class="flex gap-2 justify-end">
                  <button
                    type="button"
                    phx-click="cancel_add_entity_relationship"
                    class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
                  >
                    Save Relationship
                  </button>
                </div>
              </form>
            </div>

            <div :if={@entity_relationships == []} class="py-8">
              <.empty_state>
                <:icon><span class="hero-users h-10 w-10" /></:icon>
                <:title>No related connections</:title>
                <:description>Link this connection to other people or organizations in your network.</:description>
              </.empty_state>
            </div>

            <ul :if={@entity_relationships != []} role="list" class="divide-y divide-gray-200">
              <li :for={rel <- @entity_relationships} class="py-3">
                <div class="flex items-start justify-between">
                  <.link
                    navigate={~p"/connections/#{other_entity_id(rel, @entity.id)}"}
                    class="flex items-start gap-3 hover:bg-gray-50 -ml-2 pl-2 pr-3 py-1 rounded-md flex-1"
                  >
                    <.avatar name={other_entity_name(rel, @entity.id)} size={:sm} />
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-medium text-gray-900">{other_entity_name(rel, @entity.id)}</p>
                      <p class="text-xs text-gray-500">
                        {EntityRelationship.display_label_for(rel, @entity.id)}
                      </p>
                      <p :if={rel.notes && rel.notes != ""} class="mt-1 text-xs text-gray-400 italic truncate">
                        {rel.notes}
                      </p>
                    </div>
                  </.link>
                  <button
                    phx-click="delete_entity_relationship"
                    phx-value-id={rel.id}
                    data-confirm="Remove this relationship?"
                    class="text-gray-400 hover:text-red-500 mt-1"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                </div>
              </li>
            </ul>
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
              <form phx-submit="save_custom_field" phx-change="custom_field_type_changed" class="space-y-3">
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
                      <option value="text" selected={@new_custom_field.field_type == "text"}>Text</option>
                      <option value="date" selected={@new_custom_field.field_type == "date"}>Date</option>
                      <option value="number" selected={@new_custom_field.field_type == "number"}>Number</option>
                      <option value="boolean" selected={@new_custom_field.field_type == "boolean"}>Yes/No</option>
                      <option value="url" selected={@new_custom_field.field_type == "url"}>URL</option>
                      <option value="email" selected={@new_custom_field.field_type == "email"}>Email</option>
                      <option value="phone" selected={@new_custom_field.field_type == "phone"}>Phone</option>
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
                    <%= case @new_custom_field.field_type do %>
                      <% "date" -> %>
                        <input
                          type="date"
                          name="custom_field[value]"
                          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                        />
                      <% "number" -> %>
                        <input
                          type="number"
                          name="custom_field[value]"
                          step="any"
                          placeholder="Enter number"
                          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                        />
                      <% "boolean" -> %>
                        <select
                          name="custom_field[value]"
                          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                        >
                          <option value="">Select...</option>
                          <option value="true">Yes</option>
                          <option value="false">No</option>
                        </select>
                      <% "url" -> %>
                        <input
                          type="url"
                          name="custom_field[value]"
                          placeholder="https://example.com"
                          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                        />
                      <% "email" -> %>
                        <input
                          type="email"
                          name="custom_field[value]"
                          placeholder="email@example.com"
                          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                        />
                      <% "phone" -> %>
                        <input
                          type="tel"
                          name="custom_field[value]"
                          placeholder="+1 (555) 123-4567"
                          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                        />
                      <% _ -> %>
                        <input
                          type="text"
                          name="custom_field[value]"
                          placeholder="Enter value"
                          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                        />
                    <% end %>
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

        <!-- Sidebar with activity and reminders -->
        <div class="space-y-6">
          <!-- Activity Summary (Last Communication, Gmail Email & Event) -->
          <.card :if={@last_communication || @last_event || @last_gmail_email}>
            <:header>Activity</:header>
            <div class="space-y-4">
              <!-- Last Gmail Email (on-demand from Gmail API) -->
              <div :if={@last_gmail_email} class="flex items-start gap-3">
                <div class="flex-shrink-0">
                  <span class="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-red-500">
                    <.icon name="hero-envelope" class="h-4 w-4 text-white" />
                  </span>
                </div>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-medium text-gray-900">Last Email</p>
                  <p :if={@last_gmail_email.subject} class="text-xs text-gray-600 truncate">{@last_gmail_email.subject}</p>
                  <p class="mt-1 text-xs text-gray-400">{format_datetime(@last_gmail_email.date)}</p>
                  <p :if={@last_gmail_email.direction} class="text-xs text-gray-400">
                    {if @last_gmail_email.direction == "inbound", do: "Received", else: "Sent"}
                  </p>
                </div>
              </div>

              <!-- Last Communication (from database) -->
              <div :if={@last_communication && !@last_gmail_email} class="flex items-start gap-3">
                <div class="flex-shrink-0">
                  <span class={["inline-flex h-8 w-8 items-center justify-center rounded-lg", communication_channel_bg(@last_communication.channel)]}>
                    <.icon name={communication_channel_icon(@last_communication.channel)} class="h-4 w-4 text-white" />
                  </span>
                </div>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-medium text-gray-900">Last Communication</p>
                  <p class="text-xs text-gray-500">{String.capitalize(@last_communication.channel)}</p>
                  <p class="mt-1 text-xs text-gray-400">{format_datetime(@last_communication.sent_at)}</p>
                  <p :if={@last_communication.direction} class="text-xs text-gray-400">
                    {if @last_communication.direction == "inbound", do: "Received", else: "Sent"}
                  </p>
                </div>
              </div>

              <!-- Last Event/Meeting -->
              <div :if={@last_event} class="flex items-start gap-3">
                <div class="flex-shrink-0">
                  <span class="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-purple-100">
                    <.icon name="hero-calendar" class="h-4 w-4 text-purple-600" />
                  </span>
                </div>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-medium text-gray-900">Last {String.capitalize(@last_event.type)}</p>
                  <p :if={@last_event.title} class="text-xs text-gray-500 truncate">{@last_event.title}</p>
                  <p class="mt-1 text-xs text-gray-400">{format_datetime(@last_event.occurred_at)}</p>
                </div>
              </div>
            </div>
          </.card>

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

      <!-- Merge Modal -->
      <.modal
        :if={@merging}
        id="merge-modal"
        show
        on_cancel={JS.push("cancel_merge")}
      >
        <div class="space-y-4">
          <h3 class="text-lg font-semibold text-gray-900">
            Merge "{@entity.name}" into another connection
          </h3>
          <p class="text-sm text-gray-500">
            Select a connection to merge this one into. All identifiers (emails, phones),
            interactions, and tags will be transferred to the target connection.
            This connection will be deleted after merging.
          </p>

          <div :if={@merge_candidates == []} class="py-8 text-center">
            <p class="text-gray-500">No other connections of this type to merge with.</p>
          </div>

          <div :if={@merge_candidates != []}>
            <!-- Search input -->
            <div class="relative mb-3">
              <.icon name="hero-magnifying-glass" class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
              <input
                type="text"
                placeholder="Search connections..."
                value={@merge_search}
                phx-keyup="merge_search"
                phx-debounce="150"
                class="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md text-sm placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
              />
            </div>

            <!-- Results count -->
            <p :if={@merge_search != ""} class="text-xs text-gray-500 mb-2">
              {length(@filtered_merge_candidates)} of {length(@merge_candidates)} connections
            </p>

            <!-- No results message -->
            <div :if={@filtered_merge_candidates == [] && @merge_search != ""} class="py-6 text-center">
              <p class="text-gray-500 text-sm">No connections match "{@merge_search}"</p>
            </div>

            <!-- Candidates list -->
            <div :if={@filtered_merge_candidates != []} class="max-h-72 overflow-y-auto border border-gray-200 rounded-md">
              <ul role="list" class="divide-y divide-gray-200">
                <li :for={candidate <- @filtered_merge_candidates} class="py-3 px-2">
                  <button
                    phx-click="merge_into"
                    phx-value-target_id={candidate.id}
                    data-confirm={"Merge \"#{@entity.name}\" into \"#{candidate.name}\"? This cannot be undone."}
                    class="w-full flex items-center gap-3 p-2 rounded-md hover:bg-gray-50 text-left"
                  >
                    <.avatar name={candidate.name} size={:sm} />
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-medium text-gray-900">{candidate.name}</p>
                      <p class="text-xs text-gray-500 truncate">{candidate.description || "No description"}</p>
                    </div>
                    <.icon name="hero-arrow-right" class="h-5 w-5 text-gray-400" />
                  </button>
                </li>
              </ul>
            </div>
          </div>

          <div class="flex justify-end pt-4 border-t">
            <.button
              phx-click="cancel_merge"
              class="!bg-white !text-gray-700 ring-1 ring-gray-300 hover:!bg-gray-50"
            >
              Cancel
            </.button>
          </div>
        </div>
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

  defp fetch_last_gmail_email(user_id, identifiers) do
    # Get the first email identifier to query Gmail
    case Enum.find(identifiers, &(&1.type == "email")) do
      nil ->
        nil

      email_identifier ->
        case Gmail.get_last_email_with_contact(user_id, email_identifier.value) do
          {:ok, email_info} -> email_info
          {:error, _reason} -> nil
        end
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

  # Entity relationship helpers
  defp other_entity_id(%{source_entity_id: source_id, target_entity_id: target_id}, entity_id) do
    if entity_id == source_id, do: target_id, else: source_id
  end

  defp other_entity_name(%{source_entity_id: source_id, source_entity: source, target_entity: target}, entity_id) do
    if entity_id == source_id do
      target.name
    else
      source.name
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp changeset_error_message(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
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

  defp identifier_placeholder("email"), do: "name@example.com"
  defp identifier_placeholder("phone"), do: "+1 (555) 123-4567"
  defp identifier_placeholder(_), do: "Value"

  # Communication channel styling helpers
  defp communication_channel_icon("email"), do: "hero-envelope"
  defp communication_channel_icon("sms"), do: "hero-chat-bubble-left"
  defp communication_channel_icon("whatsapp"), do: "hero-chat-bubble-left-ellipsis"
  defp communication_channel_icon("telegram"), do: "hero-paper-airplane"
  defp communication_channel_icon("phone"), do: "hero-phone"
  defp communication_channel_icon(_), do: "hero-chat-bubble-left-right"

  defp communication_channel_bg("email"), do: "bg-red-500"
  defp communication_channel_bg("sms"), do: "bg-green-500"
  defp communication_channel_bg("whatsapp"), do: "bg-green-600"
  defp communication_channel_bg("telegram"), do: "bg-blue-500"
  defp communication_channel_bg("phone"), do: "bg-indigo-500"
  defp communication_channel_bg(_), do: "bg-gray-500"
end
