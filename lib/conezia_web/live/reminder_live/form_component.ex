defmodule ConeziaWeb.ReminderLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing reminders.
  """
  use ConeziaWeb, :live_component

  alias Conezia.Reminders

  @reminder_types [
    {"Follow Up", "follow_up"},
    {"Birthday", "birthday"},
    {"Anniversary", "anniversary"},
    {"Custom", "custom"},
    {"Event", "event"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          {if @action == :new, do: "Create a new reminder to stay in touch.", else: "Update reminder details."}
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="reminder-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          options={@reminder_types}
          required
        />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:due_at]} type="datetime-local" label="Due Date" required />
        <.input
          field={@form[:entity_id]}
          type="select"
          label="Related Contact"
          options={[{"None", ""} | @entities]}
          prompt="Select a contact (optional)"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Reminder</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{reminder: reminder} = assigns, socket) do
    changeset = Reminders.change_reminder(reminder)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:reminder_types, @reminder_types)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"reminder" => reminder_params}, socket) do
    changeset =
      socket.assigns.reminder
      |> Reminders.change_reminder(reminder_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"reminder" => reminder_params}, socket) do
    save_reminder(socket, socket.assigns.action, reminder_params)
  end

  defp save_reminder(socket, :edit, reminder_params) do
    case Reminders.update_reminder(socket.assigns.reminder, reminder_params) do
      {:ok, reminder} ->
        notify_parent({:saved, reminder})

        {:noreply,
         socket
         |> put_flash(:info, "Reminder updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_reminder(socket, :new, reminder_params) do
    reminder_params =
      reminder_params
      |> Map.put("user_id", socket.assigns.current_user.id)
      |> maybe_clear_entity_id()

    case Reminders.create_reminder(reminder_params) do
      {:ok, reminder} ->
        notify_parent({:saved, reminder})

        {:noreply,
         socket
         |> put_flash(:info, "Reminder created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp maybe_clear_entity_id(%{"entity_id" => ""} = params) do
    Map.put(params, "entity_id", nil)
  end

  defp maybe_clear_entity_id(params), do: params

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "reminder"))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
