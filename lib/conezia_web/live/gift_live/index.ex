defmodule ConeziaWeb.GiftLive.Index do
  @moduledoc """
  LiveView for listing and managing gifts.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Gifts
  alias Conezia.Gifts.Gift
  alias Conezia.Entities

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    {gifts, _meta} = Gifts.list_gifts(user.id)
    summary = Gifts.budget_summary(user.id)

    socket =
      socket
      |> assign(:page_title, "Gifts")
      |> assign(:status_filter, nil)
      |> assign(:occasion_filter, nil)
      |> assign(:budget_summary, summary)
      |> stream(:gifts, gifts)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    entity_id = params["entity_id"]

    socket
    |> assign(:page_title, "New Gift")
    |> assign(:gift, %Gift{entity_id: entity_id})
    |> assign(:entities, list_entities_for_select(socket.assigns.current_user.id))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    gift = Gifts.get_gift_for_user(id, user.id)

    if gift do
      socket
      |> assign(:page_title, "Edit Gift")
      |> assign(:gift, gift)
      |> assign(:entities, list_entities_for_select(user.id))
    else
      socket
      |> put_flash(:error, "Gift not found")
      |> push_patch(to: ~p"/gifts")
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Gifts")
    |> assign(:gift, nil)
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    user = socket.assigns.current_user
    status = if status == "", do: nil, else: status

    {gifts, _meta} = Gifts.list_gifts(user.id, status: status, occasion: socket.assigns.occasion_filter)

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> stream(:gifts, gifts, reset: true)}
  end

  def handle_event("filter_occasion", %{"occasion" => occasion}, socket) do
    user = socket.assigns.current_user
    occasion = if occasion == "", do: nil, else: occasion

    {gifts, _meta} = Gifts.list_gifts(user.id, status: socket.assigns.status_filter, occasion: occasion)

    {:noreply,
     socket
     |> assign(:occasion_filter, occasion)
     |> stream(:gifts, gifts, reset: true)}
  end

  def handle_event("update_status", %{"id" => id, "status" => new_status}, socket) do
    user = socket.assigns.current_user
    gift = Gifts.get_gift_for_user(id, user.id)

    case gift do
      nil ->
        {:noreply, put_flash(socket, :error, "Gift not found")}

      gift ->
        case Gifts.update_gift_status(gift, new_status) do
          {:ok, updated} ->
            updated = Conezia.Repo.preload(updated, :entity)
            summary = Gifts.budget_summary(user.id)

            {:noreply,
             socket
             |> stream_insert(:gifts, updated)
             |> assign(:budget_summary, summary)
             |> put_flash(:info, "Gift marked as #{new_status}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update gift status")}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    gift = Gifts.get_gift_for_user(id, user.id)

    case gift do
      nil ->
        {:noreply, put_flash(socket, :error, "Gift not found")}

      gift ->
        {:ok, _} = Gifts.delete_gift(gift)
        summary = Gifts.budget_summary(user.id)

        {:noreply,
         socket
         |> stream_delete(:gifts, gift)
         |> assign(:budget_summary, summary)
         |> put_flash(:info, "Gift deleted")}
    end
  end

  @impl true
  def handle_info({ConeziaWeb.GiftLive.FormComponent, {:saved, gift}}, socket) do
    gift = Conezia.Repo.preload(gift, :entity)
    summary = Gifts.budget_summary(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> stream_insert(:gifts, gift, at: 0)
     |> assign(:budget_summary, summary)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Gifts
        <:subtitle>Plan and track gifts for your connections</:subtitle>
        <:actions>
          <.link patch={~p"/gifts/new"}>
            <.button>
              <span class="hero-plus -ml-0.5 mr-1.5 h-5 w-5" />
              Add Gift
            </.button>
          </.link>
        </:actions>
      </.header>

      <!-- Budget Summary -->
      <div :if={@budget_summary.total_budget > 0} class="bg-white shadow ring-1 ring-gray-200 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-gray-500">Budget This Year</p>
            <p class="text-2xl font-bold text-gray-900">{format_cents(@budget_summary.total_budget)}</p>
          </div>
          <div>
            <p class="text-sm font-medium text-gray-500">Spent</p>
            <p class="text-2xl font-bold text-gray-900">{format_cents(@budget_summary.total_spent)}</p>
          </div>
          <div>
            <p class="text-sm font-medium text-gray-500">Remaining</p>
            <p class={["text-2xl font-bold", if(@budget_summary.total_budget - @budget_summary.total_spent >= 0, do: "text-green-600", else: "text-red-600")]}>
              {format_cents(@budget_summary.total_budget - @budget_summary.total_spent)}
            </p>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div class="flex items-center gap-4">
        <form phx-change="filter_status">
          <select
            name="status"
            class="block rounded-lg border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
          >
            <option value="" selected={is_nil(@status_filter)}>All Statuses</option>
            <option value="idea" selected={@status_filter == "idea"}>Ideas</option>
            <option value="purchased" selected={@status_filter == "purchased"}>Purchased</option>
            <option value="wrapped" selected={@status_filter == "wrapped"}>Wrapped</option>
            <option value="given" selected={@status_filter == "given"}>Given</option>
          </select>
        </form>
        <form phx-change="filter_occasion">
          <select
            name="occasion"
            class="block rounded-lg border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
          >
            <option value="" selected={is_nil(@occasion_filter)}>All Occasions</option>
            <option value="birthday" selected={@occasion_filter == "birthday"}>Birthday</option>
            <option value="christmas" selected={@occasion_filter == "christmas"}>Christmas</option>
            <option value="holiday" selected={@occasion_filter == "holiday"}>Holiday</option>
            <option value="anniversary" selected={@occasion_filter == "anniversary"}>Anniversary</option>
            <option value="graduation" selected={@occasion_filter == "graduation"}>Graduation</option>
            <option value="wedding" selected={@occasion_filter == "wedding"}>Wedding</option>
            <option value="baby_shower" selected={@occasion_filter == "baby_shower"}>Baby Shower</option>
            <option value="housewarming" selected={@occasion_filter == "housewarming"}>Housewarming</option>
            <option value="other" selected={@occasion_filter == "other"}>Other</option>
          </select>
        </form>
      </div>

      <!-- Gift list -->
      <div class="bg-white shadow ring-1 ring-gray-200 rounded-lg overflow-hidden">
        <ul id="gifts" phx-update="stream" role="list" class="divide-y divide-gray-200">
          <li
            :for={{dom_id, gift} <- @streams.gifts}
            id={dom_id}
            class={["px-4 py-4 sm:px-6", gift.status == "given" && "bg-gray-50"]}
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center min-w-0 gap-4">
                <span class={["flex-shrink-0 h-8 w-8 rounded-full flex items-center justify-center", status_bg(gift.status)]}>
                  <span class={["h-4 w-4 text-white", status_icon(gift.status)]} />
                </span>
                <div class="min-w-0 flex-1">
                  <p class={["text-sm font-medium", gift.status == "given" && "text-gray-500 line-through", gift.status != "given" && "text-gray-900"]}>
                    {gift.name}
                  </p>
                  <div class="mt-1 flex items-center gap-2 text-xs text-gray-500">
                    <span :if={gift.entity}>
                      For: <.link navigate={~p"/connections/#{gift.entity.id}"} class="text-indigo-600 hover:text-indigo-500">
                        {gift.entity.name}
                      </.link>
                    </span>
                    <span :if={gift.occasion_date}>
                      • {format_date(gift.occasion_date)}
                    </span>
                    <span :if={gift.budget_cents}>
                      • Budget: {format_cents(gift.budget_cents)}
                    </span>
                    <span :if={gift.actual_cost_cents}>
                      • Cost: {format_cents(gift.actual_cost_cents)}
                    </span>
                  </div>
                </div>
              </div>

              <div class="flex items-center gap-2 ml-4">
                <.badge color={occasion_color(gift.occasion)}>
                  {humanize(gift.occasion)}
                </.badge>
                <.badge color={status_color(gift.status)}>
                  {humanize(gift.status)}
                </.badge>

                <!-- Quick status buttons -->
                <div :if={gift.status != "given"} class="flex items-center gap-1">
                  <button
                    :if={gift.status == "idea"}
                    phx-click="update_status"
                    phx-value-id={gift.id}
                    phx-value-status="purchased"
                    title="Mark as purchased"
                    class="p-1 text-gray-400 hover:text-green-500"
                  >
                    <span class="hero-shopping-cart h-5 w-5" />
                  </button>
                  <button
                    :if={gift.status == "purchased"}
                    phx-click="update_status"
                    phx-value-id={gift.id}
                    phx-value-status="wrapped"
                    title="Mark as wrapped"
                    class="p-1 text-gray-400 hover:text-purple-500"
                  >
                    <span class="hero-gift h-5 w-5" />
                  </button>
                  <button
                    :if={gift.status in ["purchased", "wrapped"]}
                    phx-click="update_status"
                    phx-value-id={gift.id}
                    phx-value-status="given"
                    title="Mark as given"
                    class="p-1 text-gray-400 hover:text-green-500"
                  >
                    <span class="hero-check-circle h-5 w-5" />
                  </button>
                </div>

                <.link patch={~p"/gifts/#{gift.id}/edit"} class="p-1 text-gray-400 hover:text-gray-500">
                  <span class="hero-pencil-square h-5 w-5" />
                </.link>

                <button
                  phx-click="delete"
                  phx-value-id={gift.id}
                  data-confirm="Are you sure you want to delete this gift?"
                  class="p-1 text-gray-400 hover:text-red-500"
                >
                  <span class="hero-trash h-5 w-5" />
                </button>
              </div>
            </div>
          </li>
        </ul>

        <div :if={@streams.gifts.inserts == []} class="py-12">
          <.empty_state>
            <:icon><span class="hero-gift h-12 w-12" /></:icon>
            <:title>No gifts found</:title>
            <:description>
              {if @status_filter || @occasion_filter, do: "Try adjusting your filters.", else: "Start planning gifts for your connections."}
            </:description>
            <:action :if={is_nil(@status_filter) and is_nil(@occasion_filter)}>
              <.link patch={~p"/gifts/new"}>
                <.button>Add Gift</.button>
              </.link>
            </:action>
          </.empty_state>
        </div>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="gift-modal"
        show
        on_cancel={JS.patch(~p"/gifts")}
      >
        <.live_component
          module={ConeziaWeb.GiftLive.FormComponent}
          id={@gift.id || :new}
          title={@page_title}
          action={@live_action}
          gift={@gift}
          entities={@entities}
          current_user={@current_user}
          patch={~p"/gifts"}
        />
      </.modal>
    </div>
    """
  end

  defp list_entities_for_select(user_id) do
    {entities, _meta} = Entities.list_entities(user_id, limit: 100)
    Enum.map(entities, &{&1.name, &1.id})
  end

  defp format_cents(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_cents(_), do: "$0.00"

  defp format_date(date), do: Calendar.strftime(date, "%b %d, %Y")

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize(_), do: ""

  defp status_color("idea"), do: :gray
  defp status_color("purchased"), do: :blue
  defp status_color("wrapped"), do: :purple
  defp status_color("given"), do: :green
  defp status_color(_), do: :gray

  defp status_bg("idea"), do: "bg-gray-400"
  defp status_bg("purchased"), do: "bg-blue-500"
  defp status_bg("wrapped"), do: "bg-purple-500"
  defp status_bg("given"), do: "bg-green-500"
  defp status_bg(_), do: "bg-gray-400"

  defp status_icon("idea"), do: "hero-light-bulb"
  defp status_icon("purchased"), do: "hero-shopping-cart"
  defp status_icon("wrapped"), do: "hero-gift"
  defp status_icon("given"), do: "hero-check"
  defp status_icon(_), do: "hero-light-bulb"

  defp occasion_color("birthday"), do: :pink
  defp occasion_color("christmas"), do: :red
  defp occasion_color("holiday"), do: :red
  defp occasion_color("anniversary"), do: :indigo
  defp occasion_color("graduation"), do: :blue
  defp occasion_color("wedding"), do: :purple
  defp occasion_color("baby_shower"), do: :yellow
  defp occasion_color("housewarming"), do: :green
  defp occasion_color(_), do: :gray
end
