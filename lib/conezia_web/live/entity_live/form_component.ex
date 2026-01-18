defmodule ConeziaWeb.EntityLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing entities/contacts.
  """
  use ConeziaWeb, :live_component

  alias Conezia.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          {if @action == :new, do: "Add a new contact to your network.", else: "Update contact information."}
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
          label="Type"
          options={[{"Person", "person"}, {"Organization", "organization"}]}
          required
        />
        <.input field={@form[:description]} type="textarea" label="Description" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Contact</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{entity: entity} = assigns, socket) do
    changeset = Entities.change_entity(entity)

    {:ok,
     socket
     |> assign(assigns)
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

  def handle_event("save", %{"entity" => entity_params}, socket) do
    save_entity(socket, socket.assigns.action, entity_params)
  end

  defp save_entity(socket, :edit, entity_params) do
    case Entities.update_entity(socket.assigns.entity, entity_params) do
      {:ok, entity} ->
        notify_parent({:saved, entity})

        {:noreply,
         socket
         |> put_flash(:info, "Contact updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_entity(socket, :new, entity_params) do
    entity_params = Map.put(entity_params, "owner_id", socket.assigns.current_user.id)

    case Entities.create_entity(entity_params) do
      {:ok, entity} ->
        notify_parent({:saved, entity})

        {:noreply,
         socket
         |> put_flash(:info, "Contact created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "entity"))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
