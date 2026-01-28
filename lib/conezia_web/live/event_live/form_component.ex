defmodule ConeziaWeb.EventLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing events.
  """
  use ConeziaWeb, :live_component

  alias Conezia.Events

  @event_types [
    {"Birthday", "birthday"},
    {"Anniversary", "anniversary"},
    {"Holiday", "holiday"},
    {"Celebration", "celebration"},
    {"Meeting", "meeting"},
    {"Dinner", "dinner"},
    {"Party", "party"},
    {"Wedding", "wedding"},
    {"Memorial", "memorial"},
    {"Reunion", "reunion"},
    {"Trip", "trip"},
    {"Other", "other"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          {if @action == :new, do: "Create a new event.", else: "Update event details."}
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="event-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          options={@event_types}
          required
        />

        <.input field={@form[:all_day]} type="checkbox" label="All day event" />

        <div :if={@all_day} class="grid grid-cols-1 gap-4">
          <.input field={@form[:starts_at]} type="date" label="Date" value={@all_day_date} required />
        </div>
        <div :if={!@all_day} class="grid grid-cols-2 gap-4">
          <.input field={@form[:starts_at]} type="datetime-local" label="Start" required />
          <.input field={@form[:ends_at]} type="datetime-local" label="End (optional)" />
        </div>
        <.input field={@form[:location]} type="text" label="Location (optional)" />

        <.input
          field={@form[:entity_ids]}
          type="select"
          label="Connected to"
          options={@entities}
          multiple
        />

        <.input :if={!@remind_yearly} field={@form[:is_recurring]} type="checkbox" label="Recurring event" />
        <.input :if={!@is_recurring} field={@form[:remind_yearly]} type="checkbox" label="Remind me every year" />

        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:notes]} type="textarea" label="Notes" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Event</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{event: event} = assigns, socket) do
    changeset = Events.change_event(event)

    entity_ids =
      case event do
        %{entities: entities} when is_list(entities) -> Enum.map(entities, & &1.id)
        _ -> []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:event_types, @event_types)
     |> assign(:selected_entity_ids, entity_ids)
     |> assign(:all_day, event.all_day || false)
     |> assign(:all_day_date, if(event.starts_at, do: Calendar.strftime(event.starts_at, "%Y-%m-%d"), else: ""))
     |> assign(:is_recurring, event.is_recurring || false)
     |> assign(:remind_yearly, event.remind_yearly || false)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    all_day = event_params["all_day"] == "true"
    raw_date = event_params["starts_at"]

    changeset =
      socket.assigns.event
      |> Events.change_event(maybe_convert_date_to_datetime(event_params))
      |> Map.put(:action, :validate)

    is_recurring = event_params["is_recurring"] == "true"
    remind_yearly = event_params["remind_yearly"] == "true"

    # Preserve the raw date string so the date input keeps its value
    all_day_date = if all_day, do: raw_date || socket.assigns.all_day_date, else: raw_date || ""

    {:noreply,
     socket
     |> assign(:all_day, all_day)
     |> assign(:all_day_date, all_day_date)
     |> assign(:is_recurring, is_recurring)
     |> assign(:remind_yearly, remind_yearly)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"event" => event_params}, socket) do
    event_params = maybe_convert_date_to_datetime(event_params)
    save_event(socket, socket.assigns.action, event_params)
  end

  defp save_event(socket, :edit, event_params) do
    case Events.update_event(socket.assigns.event, event_params) do
      {:ok, event} ->
        notify_parent({:saved, event})

        {:noreply,
         socket
         |> put_flash(:info, "Event updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_event(socket, :new, event_params) do
    event_params = Map.put(event_params, "user_id", socket.assigns.current_user.id)

    case Events.create_event(event_params) do
      {:ok, event} ->
        notify_parent({:saved, event})

        {:noreply,
         socket
         |> put_flash(:info, "Event created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # When all_day is true, the form sends a date string (e.g. "2026-03-15")
  # instead of a datetime-local string. Convert it to a full datetime for starts_at.
  defp maybe_convert_date_to_datetime(%{"all_day" => "true", "starts_at" => date_str} = params)
       when is_binary(date_str) and byte_size(date_str) == 10 do
    Map.put(params, "starts_at", date_str <> "T00:00")
  end

  defp maybe_convert_date_to_datetime(params), do: params

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "event"))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
