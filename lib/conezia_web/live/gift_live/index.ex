defmodule ConeziaWeb.GiftLive.Index do
  @moduledoc """
  LiveView for gift planning. Shows upcoming occasions from connections'
  important dates and allows planning gifts for them.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Gifts
  alias Conezia.Gifts.Gift
  alias Conezia.Entities

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    occasions = Entities.list_upcoming_occasions(user.id, 90)
    {gifts, _meta} = Gifts.list_gifts(user.id)
    summary = Gifts.budget_summary(user.id)

    socket =
      socket
      |> assign(:page_title, "Gifts")
      |> assign(:occasions, occasions)
      |> assign(:status_filter, nil)
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
    occasion = params["occasion"]
    occasion_date = parse_date(params["occasion_date"])

    gift = %Gift{
      entity_id: entity_id,
      occasion: occasion,
      occasion_date: occasion_date
    }

    socket
    |> assign(:page_title, "Plan Gift")
    |> assign(:gift, gift)
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

    {gifts, _meta} = Gifts.list_gifts(user.id, status: status)

    {:noreply,
     socket
     |> assign(:status_filter, status)
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
    user = socket.assigns.current_user
    gift = Conezia.Repo.preload(gift, :entity)
    summary = Gifts.budget_summary(user.id)
    occasions = Entities.list_upcoming_occasions(user.id, 90)

    {:noreply,
     socket
     |> stream_insert(:gifts, gift, at: 0)
     |> assign(:budget_summary, summary)
     |> assign(:occasions, occasions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Gifts
        <:subtitle>Plan gifts based on your connections' upcoming occasions</:subtitle>
      </.header>

      <!-- Upcoming Occasions -->
      <div class="bg-white shadow ring-1 ring-gray-200 rounded-lg overflow-hidden">
        <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
          <h3 class="text-sm font-semibold text-gray-900">Upcoming Occasions (Next 90 Days)</h3>
        </div>

        <div :if={@occasions == []} class="py-8">
          <div class="text-center">
            <span class="hero-calendar h-10 w-10 text-gray-400 mx-auto" />
            <p class="mt-2 text-sm text-gray-500">No upcoming occasions found.</p>
            <p class="text-xs text-gray-400 mt-1">
              Add birthdays and anniversaries to your connections' Important Dates.
            </p>
          </div>
        </div>

        <ul :if={@occasions != []} role="list" class="divide-y divide-gray-200">
          <li :for={occasion <- @occasions} class="px-4 py-3 hover:bg-gray-50">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3 min-w-0">
                <span class={["flex-shrink-0 h-9 w-9 rounded-full flex items-center justify-center", occasion_bg(occasion.key)]}>
                  <span class={["h-4 w-4 text-white", occasion_icon(occasion.key)]} />
                </span>
                <div class="min-w-0">
                  <p class="text-sm font-medium text-gray-900">
                    <.link navigate={~p"/connections/#{occasion.entity.id}"} class="hover:text-indigo-600">
                      {occasion.entity.name}
                    </.link>
                    <span class="font-normal text-gray-500"> — {occasion.name}</span>
                  </p>
                  <p class="text-xs text-gray-500">
                    {format_date(occasion.next_date)}
                    <span class={["ml-1 font-medium", days_away_color(occasion.next_date)]}>
                      ({days_away_label(occasion.next_date)})
                    </span>
                  </p>
                </div>
              </div>
              <.link
                patch={~p"/gifts/new?entity_id=#{occasion.entity.id}&occasion=#{occasion.key}&occasion_date=#{Date.to_iso8601(occasion.next_date)}"}
                class="inline-flex items-center gap-1 rounded-md bg-indigo-50 px-2.5 py-1.5 text-xs font-semibold text-indigo-600 hover:bg-indigo-100"
              >
                <span class="hero-gift h-3.5 w-3.5" />
                Plan Gift
              </.link>
            </div>
          </li>
        </ul>
      </div>

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

      <!-- Planned Gifts -->
      <div class="bg-white shadow ring-1 ring-gray-200 rounded-lg overflow-hidden">
        <div class="px-4 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between">
          <h3 class="text-sm font-semibold text-gray-900">Planned Gifts</h3>
          <form phx-change="filter_status">
            <select
              name="status"
              class="block rounded-md border-gray-300 text-xs focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option value="" selected={is_nil(@status_filter)}>All</option>
              <option value="idea" selected={@status_filter == "idea"}>Ideas</option>
              <option value="purchased" selected={@status_filter == "purchased"}>Purchased</option>
              <option value="wrapped" selected={@status_filter == "wrapped"}>Wrapped</option>
              <option value="given" selected={@status_filter == "given"}>Given</option>
            </select>
          </form>
        </div>

        <ul id="gifts" phx-update="stream" role="list" class="divide-y divide-gray-200">
          <li
            :for={{dom_id, gift} <- @streams.gifts}
            id={dom_id}
            class={["px-4 py-4 sm:px-6 group", gift.status == "given" && "bg-gray-50"]}
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center min-w-0 gap-3">
                <span class={["flex-shrink-0 h-8 w-8 rounded-full flex items-center justify-center", status_bg(gift.status)]}>
                  <span class={["h-4 w-4 text-white", status_icon(gift.status)]} />
                </span>
                <div class="min-w-0 flex-1">
                  <p class={["text-sm font-medium", gift.status == "given" && "text-gray-500 line-through", gift.status != "given" && "text-gray-900"]}>
                    {gift.name}
                  </p>
                  <div class="mt-0.5 flex items-center gap-2 text-xs text-gray-500">
                    <span :if={gift.entity}>
                      For: <.link navigate={~p"/connections/#{gift.entity.id}"} class="text-indigo-600 hover:text-indigo-500">
                        {gift.entity.name}
                      </.link>
                    </span>
                    <span :if={gift.occasion_date}>• {format_date(gift.occasion_date)}</span>
                    <span :if={gift.budget_cents}>• {format_cents(gift.budget_cents)}</span>
                  </div>
                </div>
              </div>

              <div class="flex items-center gap-2 ml-4">
                <.badge color={occasion_color(gift.occasion)}>{humanize(gift.occasion)}</.badge>
                <.badge color={status_color(gift.status)}>{humanize(gift.status)}</.badge>

                <div :if={gift.status != "given"} class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
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

                <.link patch={~p"/gifts/#{gift.id}/edit"} class="p-1 text-gray-400 hover:text-gray-500 opacity-0 group-hover:opacity-100 transition-opacity">
                  <span class="hero-pencil-square h-5 w-5" />
                </.link>

                <button
                  phx-click="delete"
                  phx-value-id={gift.id}
                  data-confirm="Delete this gift?"
                  class="p-1 text-gray-400 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <span class="hero-trash h-5 w-5" />
                </button>
              </div>
            </div>
          </li>
        </ul>

        <div :if={@streams.gifts.inserts == []} class="py-8">
          <div class="text-center">
            <span class="hero-gift h-10 w-10 text-gray-400 mx-auto" />
            <p class="mt-2 text-sm text-gray-500">
              {if @status_filter, do: "No gifts match this filter.", else: "No gifts planned yet. Click \"Plan Gift\" on an upcoming occasion above."}
            </p>
          </div>
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
    {entities, _meta} = Entities.list_entities(user_id, limit: 10_000)
    Enum.map(entities, &{&1.name, &1.id})
  end

  defp parse_date(nil), do: nil
  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp format_cents(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_cents(_), do: "$0.00"

  defp format_date(date), do: Calendar.strftime(date, "%b %d, %Y")

  defp days_away_label(date) do
    days = Date.diff(date, Date.utc_today())

    cond do
      days == 0 -> "Today!"
      days == 1 -> "Tomorrow"
      days <= 7 -> "#{days} days"
      days <= 30 -> "#{div(days, 7)} weeks"
      true -> "#{div(days, 30)} months"
    end
  end

  defp days_away_color(date) do
    days = Date.diff(date, Date.utc_today())

    cond do
      days <= 7 -> "text-red-600"
      days <= 14 -> "text-orange-600"
      days <= 30 -> "text-yellow-600"
      true -> "text-gray-500"
    end
  end

  defp humanize(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
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

  defp occasion_bg("birthday"), do: "bg-pink-500"
  defp occasion_bg("anniversary"), do: "bg-indigo-500"
  defp occasion_bg(_), do: "bg-gray-500"

  defp occasion_icon("birthday"), do: "hero-cake"
  defp occasion_icon("anniversary"), do: "hero-heart"
  defp occasion_icon(_), do: "hero-calendar"
end
