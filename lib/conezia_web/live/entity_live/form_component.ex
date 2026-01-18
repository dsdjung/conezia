defmodule ConeziaWeb.EntityLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing entities/connections.
  """
  use ConeziaWeb, :live_component

  alias Conezia.Entities
  alias Conezia.Entities.Relationship

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          {if @action == :new, do: "Add a new connection to your network.", else: "Update connection information."}
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="entity-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input
          field={@form[:type]}
          type="select"
          label="Entity Type"
          options={[{"Person", "person"}, {"Organization", "organization"}]}
          required
        />
        <.input field={@form[:description]} type="textarea" label="Description" />

        <div class="border-t border-gray-200 pt-4 mt-4">
          <h3 class="text-sm font-medium text-gray-900 mb-3">Relationship</h3>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700">Relationship Type</label>
              <select
                name="relationship[type]"
                phx-change="relationship_type_changed"
                phx-target={@myself}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              >
                <option value="">Select type...</option>
                <option :for={{label, value} <- relationship_type_options()} value={value} selected={@relationship_type == value}>
                  {label}
                </option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Subtype</label>
              <select
                name="relationship[subtype]"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                disabled={@relationship_type == "" or @relationship_type == nil}
              >
                <option value="">Select subtype...</option>
                <option :for={{label, value} <- relationship_subtype_options(@relationship_type)} value={value} selected={@relationship_subtype == value}>
                  {label}
                </option>
              </select>
            </div>
          </div>
          <div class="mt-3">
            <label class="block text-sm font-medium text-gray-700">Custom Label (optional)</label>
            <input
              type="text"
              name="relationship[custom_label]"
              value={@relationship_custom_label}
              placeholder="e.g., College roommate, Team lead"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            />
            <p class="mt-1 text-xs text-gray-500">Add a custom label if the options above don't fit</p>
          </div>
        </div>

        <:actions>
          <.button phx-disable-with="Saving...">Save Connection</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{entity: entity} = assigns, socket) do
    changeset = Entities.change_entity(entity)
    relationship = Map.get(assigns, :relationship)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:relationship_type, relationship && relationship.type)
     |> assign(:relationship_subtype, relationship && relationship.subtype)
     |> assign(:relationship_custom_label, relationship && relationship.custom_label)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"entity" => entity_params}, socket) do
    changeset =
      socket.assigns.entity
      |> Entities.change_entity(entity_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("relationship_type_changed", %{"relationship" => %{"type" => type}}, socket) do
    {:noreply,
     socket
     |> assign(:relationship_type, type)
     |> assign(:relationship_subtype, nil)}
  end

  def handle_event("save", %{"entity" => entity_params} = params, socket) do
    relationship_params = Map.get(params, "relationship", %{})
    save_entity(socket, socket.assigns.action, entity_params, relationship_params)
  end

  defp save_entity(socket, :edit, entity_params, relationship_params) do
    case Entities.update_entity(socket.assigns.entity, entity_params) do
      {:ok, entity} ->
        save_or_update_relationship(socket, entity, relationship_params)
        notify_parent({:saved, entity})

        {:noreply,
         socket
         |> put_flash(:info, "Connection updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_entity(socket, :new, entity_params, relationship_params) do
    entity_params = Map.put(entity_params, "owner_id", socket.assigns.current_user.id)

    case Entities.create_entity(entity_params) do
      {:ok, entity} ->
        save_or_update_relationship(socket, entity, relationship_params)
        notify_parent({:saved, entity})

        {:noreply,
         socket
         |> put_flash(:info, "Connection created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_or_update_relationship(socket, entity, params) do
    user = socket.assigns.current_user
    type = params["type"]

    if type && type != "" do
      case Entities.get_relationship_for_entity(user.id, entity.id) do
        nil ->
          Entities.create_relationship(%{
            user_id: user.id,
            entity_id: entity.id,
            type: type,
            subtype: params["subtype"],
            custom_label: params["custom_label"],
            status: "active"
          })

        existing ->
          Entities.update_relationship(existing, %{
            type: type,
            subtype: params["subtype"],
            custom_label: params["custom_label"]
          })
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "entity"))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp relationship_type_options do
    [
      {"Family", "family"},
      {"Friend", "friend"},
      {"Colleague", "colleague"},
      {"Professional", "professional"},
      {"Community", "community"},
      {"Service Provider", "service"},
      {"Acquaintance", "acquaintance"},
      {"Other", "other"}
    ]
  end

  defp relationship_subtype_options(nil), do: []
  defp relationship_subtype_options(""), do: []
  defp relationship_subtype_options(type) do
    Relationship.subtypes_for_type(type)
    |> Enum.map(fn subtype ->
      {humanize_subtype(subtype), subtype}
    end)
  end

  defp humanize_subtype(subtype) when is_binary(subtype) do
    subtype
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
