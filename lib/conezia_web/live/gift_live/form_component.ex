defmodule ConeziaWeb.GiftLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing gifts.
  """
  use ConeziaWeb, :live_component

  alias Conezia.Gifts

  @occasions [
    {"Birthday", "birthday"},
    {"Christmas", "christmas"},
    {"Holiday", "holiday"},
    {"Anniversary", "anniversary"},
    {"Graduation", "graduation"},
    {"Wedding", "wedding"},
    {"Baby Shower", "baby_shower"},
    {"Housewarming", "housewarming"},
    {"Other", "other"}
  ]

  @statuses [
    {"Idea", "idea"},
    {"Purchased", "purchased"},
    {"Wrapped", "wrapped"},
    {"Given", "given"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          {if @action == :new, do: "Plan a gift for someone special.", else: "Update gift details."}
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="gift-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:entity_id]}
          type="select"
          label="For"
          options={@entities}
          required
        />
        <.input field={@form[:name]} type="text" label="Gift Idea" required />
        <.input
          field={@form[:occasion]}
          type="select"
          label="Occasion"
          options={@occasions}
          required
        />
        <.input field={@form[:occasion_date]} type="date" label="Occasion Date" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={@statuses}
        />
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:budget_cents]} type="number" label="Budget (cents)" />
          <.input field={@form[:actual_cost_cents]} type="number" label="Actual Cost (cents)" />
        </div>
        <.input field={@form[:url]} type="url" label="Link (optional)" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:notes]} type="textarea" label="Notes" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Gift</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{gift: gift} = assigns, socket) do
    changeset = Gifts.change_gift(gift)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:occasions, @occasions)
     |> assign(:statuses, @statuses)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"gift" => gift_params}, socket) do
    changeset =
      socket.assigns.gift
      |> Gifts.change_gift(gift_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"gift" => gift_params}, socket) do
    save_gift(socket, socket.assigns.action, gift_params)
  end

  defp save_gift(socket, :edit, gift_params) do
    case Gifts.update_gift(socket.assigns.gift, gift_params) do
      {:ok, gift} ->
        notify_parent({:saved, gift})

        {:noreply,
         socket
         |> put_flash(:info, "Gift updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_gift(socket, :new, gift_params) do
    gift_params = Map.put(gift_params, "user_id", socket.assigns.current_user.id)

    case Gifts.create_gift(gift_params) do
      {:ok, gift} ->
        notify_parent({:saved, gift})

        {:noreply,
         socket
         |> put_flash(:info, "Gift created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "gift"))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
