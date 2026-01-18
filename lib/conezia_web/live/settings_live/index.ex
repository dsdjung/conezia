defmodule ConeziaWeb.SettingsLive.Index do
  @moduledoc """
  LiveView for user settings, including external service integrations.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Integrations
  alias Conezia.ExternalAccounts

  @tabs ~w(integrations account)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:current_tab, "integrations")
      |> assign_services(user)
      |> assign_import_jobs(user)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _url, socket) when tab in @tabs do
    {:noreply, assign(socket, :current_tab, tab)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("sync", %{"id" => account_id}, socket) do
    user = socket.assigns.current_user

    case ExternalAccounts.get_external_account_for_user(account_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Account not found")}

      account ->
        case Integrations.trigger_sync(account) do
          {:ok, _job} ->
            socket =
              socket
              |> put_flash(:info, "Sync started! Check back for progress.")
              |> assign_import_jobs(user)

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start sync: #{reason}")}
        end
    end
  end

  def handle_event("disconnect", %{"id" => account_id}, socket) do
    user = socket.assigns.current_user

    case ExternalAccounts.get_external_account_for_user(account_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Account not found")}

      account ->
        case Integrations.disconnect_service(account) do
          {:ok, _} ->
            socket =
              socket
              |> put_flash(:info, "Service disconnected successfully")
              |> assign_services(user)

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to disconnect: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Settings
        <:subtitle>Manage your account and connected services</:subtitle>
      </.header>

      <!-- Tabs -->
      <div class="border-b border-gray-200">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <.link
            patch={~p"/settings/integrations"}
            class={[
              "whitespace-nowrap border-b-2 py-4 px-1 text-sm font-medium",
              @current_tab == "integrations" && "border-indigo-500 text-indigo-600",
              @current_tab != "integrations" && "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700"
            ]}
          >
            <span class="hero-puzzle-piece -ml-0.5 mr-2 h-5 w-5 inline" />
            Integrations
          </.link>
          <.link
            patch={~p"/settings/account"}
            class={[
              "whitespace-nowrap border-b-2 py-4 px-1 text-sm font-medium",
              @current_tab == "account" && "border-indigo-500 text-indigo-600",
              @current_tab != "account" && "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700"
            ]}
          >
            <span class="hero-user-circle -ml-0.5 mr-2 h-5 w-5 inline" />
            Account
          </.link>
        </nav>
      </div>

      <!-- Tab Content -->
      <div :if={@current_tab == "integrations"}>
        <.integrations_content services={@services} import_jobs={@import_jobs} />
      </div>

      <div :if={@current_tab == "account"}>
        <.account_content current_user={@current_user} />
      </div>
    </div>
    """
  end

  # Integrations Tab Content
  attr :services, :list, required: true
  attr :import_jobs, :list, required: true

  defp integrations_content(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Available Services -->
      <.card>
        <:header>Connected Services</:header>
        <p class="text-sm text-gray-500 mb-6">
          Connect your accounts to import and sync your relationships.
        </p>

        <div class="space-y-4">
          <div
            :for={service <- @services}
            class="flex items-center justify-between py-4 border-b border-gray-100 last:border-0"
          >
            <div class="flex items-center gap-4">
              <div class={[
                "flex-shrink-0 p-2 rounded-lg",
                service_bg_color(service.status)
              ]}>
                <span class={[service.icon, "h-6 w-6", service_icon_color(service.status)]} />
              </div>
              <div>
                <p class="font-medium text-gray-900">{service.display_name}</p>
                <p class="text-sm text-gray-500">
                  <%= cond do %>
                    <% service.status == :connected -> %>
                      Connected
                      <%= if service.account && service.account.last_synced_at do %>
                        • Last synced {format_relative_time(service.account.last_synced_at)}
                      <% end %>
                    <% service.status == :coming_soon -> %>
                      Coming soon
                    <% true -> %>
                      Not connected
                  <% end %>
                </p>
              </div>
            </div>

            <div class="flex items-center gap-2">
              <%= cond do %>
                <% service.status == :connected -> %>
                  <button
                    phx-click="sync"
                    phx-value-id={service.account.id}
                    class="inline-flex items-center rounded-md bg-white px-2.5 py-1.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                  >
                    <span class="hero-arrow-path -ml-0.5 mr-1.5 h-4 w-4" />
                    Sync
                  </button>
                  <button
                    phx-click="disconnect"
                    phx-value-id={service.account.id}
                    data-confirm="Are you sure you want to disconnect this service?"
                    class="inline-flex items-center rounded-md bg-white px-2.5 py-1.5 text-sm font-semibold text-red-600 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                  >
                    Disconnect
                  </button>
                <% service.status == :coming_soon -> %>
                  <.badge color={:gray}>Coming Soon</.badge>
                <% true -> %>
                  <.link href={~p"/integrations/#{service.service}/authorize"}>
                    <.button class="text-sm px-3 py-1.5">
                      <span class="hero-plus -ml-0.5 mr-1.5 h-4 w-4" />
                      Connect
                    </.button>
                  </.link>
              <% end %>
            </div>
          </div>
        </div>
      </.card>

      <!-- Import History -->
      <.card>
        <:header>Import History</:header>
        <div :if={@import_jobs == []} class="py-8">
          <.empty_state>
            <:icon><span class="hero-arrow-down-tray h-12 w-12" /></:icon>
            <:title>No imports yet</:title>
            <:description>Connect a service and sync to see your import history.</:description>
          </.empty_state>
        </div>

        <table :if={@import_jobs != []} class="min-w-full divide-y divide-gray-200">
          <thead>
            <tr>
              <th class="py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Source
              </th>
              <th class="py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Records
              </th>
              <th class="py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Date
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={job <- @import_jobs}>
              <td class="py-4">
                <span class="text-sm font-medium text-gray-900">
                  {humanize_source(job.source)}
                </span>
              </td>
              <td class="py-4">
                <.badge color={status_color(job.status)}>
                  {String.capitalize(job.status)}
                </.badge>
              </td>
              <td class="py-4 text-sm text-gray-500">
                {job.created_records} created, {job.merged_records} merged
              </td>
              <td class="py-4 text-sm text-gray-500">
                {format_datetime(job.inserted_at)}
              </td>
            </tr>
          </tbody>
        </table>
      </.card>
    </div>
    """
  end

  # Account Tab Content
  attr :current_user, :map, required: true

  defp account_content(assigns) do
    ~H"""
    <.card>
      <:header>Account Information</:header>
      <dl class="divide-y divide-gray-100">
        <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
          <dt class="text-sm font-medium text-gray-900">Email</dt>
          <dd class="mt-1 text-sm text-gray-700 sm:col-span-2 sm:mt-0">
            {@current_user.email}
          </dd>
        </div>
        <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
          <dt class="text-sm font-medium text-gray-900">Name</dt>
          <dd class="mt-1 text-sm text-gray-700 sm:col-span-2 sm:mt-0">
            {@current_user.name || "Not set"}
          </dd>
        </div>
        <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
          <dt class="text-sm font-medium text-gray-900">Member since</dt>
          <dd class="mt-1 text-sm text-gray-700 sm:col-span-2 sm:mt-0">
            {format_date(@current_user.inserted_at)}
          </dd>
        </div>
      </dl>
    </.card>
    """
  end

  # Private helpers

  defp assign_services(socket, user) do
    services = Integrations.list_available_services(user.id)
    assign(socket, :services, services)
  end

  defp assign_import_jobs(socket, user) do
    jobs = Integrations.list_import_jobs(user.id, limit: 10)
    assign(socket, :import_jobs, jobs)
  end

  defp service_bg_color(:connected), do: "bg-green-100"
  defp service_bg_color(:coming_soon), do: "bg-gray-100"
  defp service_bg_color(_), do: "bg-gray-100"

  defp service_icon_color(:connected), do: "text-green-600"
  defp service_icon_color(:coming_soon), do: "text-gray-400"
  defp service_icon_color(_), do: "text-gray-600"

  defp status_color("completed"), do: :green
  defp status_color("processing"), do: :blue
  defp status_color("pending"), do: :gray
  defp status_color("failed"), do: :red
  defp status_color(_), do: :gray

  defp humanize_source(source) when is_binary(source) do
    source
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize_source(_), do: "Unknown"

  defp format_datetime(nil), do: "N/A"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp format_date(nil), do: "N/A"
  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp format_relative_time(nil), do: "never"
  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
