defmodule ConeziaWeb.EntityLive.GiftSectionComponent do
  @moduledoc """
  LiveComponent for displaying and managing gifts on the entity show page.
  """
  use ConeziaWeb, :live_component

  alias Conezia.Gifts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">Gifts</h3>
        <.link
          navigate={~p"/gifts/new?entity_id=#{@entity.id}"}
          class="text-sm font-medium text-indigo-600 hover:text-indigo-500"
        >
          Add Gift →
        </.link>
      </div>

      <div :if={@gifts == []} class="py-6">
        <p class="text-sm text-gray-500 text-center">No gifts planned yet.</p>
      </div>

      <ul :if={@gifts != []} role="list" class="divide-y divide-gray-200">
        <li :for={gift <- @gifts} class="py-3 group">
          <div class="flex items-start justify-between">
            <div class="flex items-start gap-3 min-w-0 flex-1">
              <span class={["flex-shrink-0 h-7 w-7 rounded-full flex items-center justify-center", status_bg(gift.status)]}>
                <span class={["h-3.5 w-3.5 text-white", status_icon(gift.status)]} />
              </span>
              <div class="min-w-0 flex-1">
                <p class={["text-sm font-medium", gift.status == "given" && "text-gray-500 line-through", gift.status != "given" && "text-gray-900"]}>
                  {gift.name}
                </p>
                <div class="mt-0.5 flex flex-wrap items-center gap-x-2 text-xs text-gray-500">
                  <span>{humanize(gift.occasion)}</span>
                  <span :if={gift.occasion_date}>• {Calendar.strftime(gift.occasion_date, "%b %d, %Y")}</span>
                  <span :if={gift.budget_cents}>• {format_cents(gift.budget_cents)}</span>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-1 ml-2">
              <.badge color={status_color(gift.status)} class="text-xs">
                {humanize(gift.status)}
              </.badge>
              <button
                :if={gift.status != "given"}
                phx-click="advance_gift_status"
                phx-value-id={gift.id}
                title={"Mark as #{next_status(gift.status)}"}
                class="p-1 text-gray-400 hover:text-green-500 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <span class="hero-arrow-right h-4 w-4" />
              </button>
            </div>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    gifts = Gifts.list_gifts_for_entity(assigns.entity.id, assigns.current_user.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:gifts, gifts)}
  end

  defp format_cents(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_cents(_), do: ""

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

  defp next_status("idea"), do: "purchased"
  defp next_status("purchased"), do: "wrapped"
  defp next_status("wrapped"), do: "given"
  defp next_status(_), do: "idea"
end
