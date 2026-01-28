defmodule Conezia.Workers.CalendarSyncWorker do
  @moduledoc """
  Oban worker for two-way calendar synchronization.

  Handles:
  - Importing events from external calendars (Google Calendar, iCloud Calendar)
  - Exporting local events to external calendars
  - Deduplication based on external_id and title/date matching
  """
  use Oban.Worker, queue: :sync, max_attempts: 3

  alias Conezia.Events
  alias Conezia.Events.Event
  alias Conezia.ExternalAccounts
  alias Conezia.ExternalAccounts.ExternalAccount
  alias Conezia.Integrations
  alias Conezia.Integrations.Providers.Google
  alias Conezia.Integrations.Providers.ICloudCalendar
  alias Conezia.Repo

  require Logger

  @pubsub Conezia.PubSub
  @topic_prefix "calendar_sync:"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"external_account_id" => account_id, "user_id" => user_id} = args}) do
    direction = Map.get(args, "direction", "both")

    case ExternalAccounts.get_external_account(account_id) do
      nil ->
        {:error, :external_account_not_found}

      account ->
        if calendar_service?(account.service_name) do
          process_calendar_sync(account, user_id, direction)
        else
          {:error, "Service #{account.service_name} does not support calendar sync"}
        end
    end
  end

  defp calendar_service?(service_name), do: service_name in ["google", "icloud_calendar"]

  defp process_calendar_sync(account, user_id, direction) do
    broadcast_status(user_id, :started, %{account_id: account.id, direction: direction})

    try do
      with {:ok, refreshed_account} <- Integrations.refresh_tokens_if_needed(account),
           {:ok, access_token} <- Integrations.get_access_token(refreshed_account) do
        result =
          case direction do
            "import" -> import_events(refreshed_account, user_id, access_token)
            "export" -> export_events(refreshed_account, user_id, access_token)
            "both" -> sync_bidirectional(refreshed_account, user_id, access_token)
          end

        case result do
          {:ok, stats} ->
            ExternalAccounts.mark_synced(refreshed_account)
            broadcast_status(user_id, :completed, %{account_id: account.id, stats: stats})
            :ok

          {:error, reason} ->
            ExternalAccounts.mark_error(refreshed_account, to_string(reason))
            broadcast_status(user_id, :failed, %{account_id: account.id, error: to_string(reason)})
            {:error, reason}
        end
      else
        {:error, reason} ->
          broadcast_status(user_id, :failed, %{account_id: account.id, error: to_string(reason)})
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Calendar sync error: #{Exception.message(e)}")
        broadcast_status(user_id, :failed, %{account_id: account.id, error: Exception.message(e)})
        {:error, e}
    end
  end

  # ============================================================================
  # Import Events
  # ============================================================================

  defp import_events(%ExternalAccount{service_name: "google"} = account, user_id, access_token) do
    case Google.fetch_calendar_events(access_token) do
      {:ok, external_events, _sync_token} ->
        stats = import_external_events(external_events, user_id, account)
        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_events(%ExternalAccount{service_name: "icloud_calendar"} = account, user_id, access_token) do
    # For iCloud, access_token is app_password and we need apple_id from refresh_token
    case Integrations.get_refresh_token(account) do
      {:ok, apple_id} ->
        case ICloudCalendar.fetch_calendar_events(access_token, apple_id: apple_id) do
          {:ok, external_events, _} ->
            stats = import_external_events(external_events, user_id, account)
            {:ok, stats}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_events(%ExternalAccount{service_name: service}, _user_id, _access_token) do
    {:error, "Unsupported calendar service: #{service}"}
  end

  defp import_external_events(external_events, user_id, account) do
    Enum.reduce(external_events, %{created: 0, updated: 0, skipped: 0}, fn ext_event, acc ->
      case import_single_event(ext_event, user_id, account) do
        {:ok, :created} -> %{acc | created: acc.created + 1}
        {:ok, :updated} -> %{acc | updated: acc.updated + 1}
        {:ok, :skipped} -> %{acc | skipped: acc.skipped + 1}
        {:error, _} -> acc
      end
    end)
  end

  defp import_single_event(ext_event, user_id, account) do
    external_id = ext_event[:external_id] || ext_event["external_id"]

    # Check for existing by external_id first
    case Events.find_by_external_id(user_id, external_id) do
      nil ->
        # Try fuzzy match by title + date
        title = ext_event[:title] || ext_event["title"]
        starts_at = ext_event[:starts_at] || ext_event["starts_at"]

        case Events.find_matching_event(user_id, %{title: title, starts_at: starts_at}) do
          nil ->
            create_event_from_external(ext_event, user_id, account)

          existing ->
            merge_event_from_external(existing, ext_event, account)
        end

      existing ->
        merge_event_from_external(existing, ext_event, account)
    end
  end

  defp create_event_from_external(ext_event, user_id, account) do
    attrs = %{
      title: ext_event[:title] || ext_event["title"],
      description: ext_event[:description] || ext_event["description"],
      location: ext_event[:location] || ext_event["location"],
      starts_at: ext_event[:starts_at] || ext_event["starts_at"],
      ends_at: ext_event[:ends_at] || ext_event["ends_at"],
      all_day: ext_event[:all_day] || ext_event["all_day"] || false,
      type: "other",
      user_id: user_id,
      external_id: ext_event[:external_id] || ext_event["external_id"],
      external_account_id: account.id,
      sync_status: "synced",
      last_synced_at: DateTime.utc_now(),
      sync_metadata: %{
        "etag" => ext_event[:etag] || ext_event["etag"],
        "source" => account.service_name
      }
    }

    case Events.create_event(attrs) do
      {:ok, _event} -> {:ok, :created}
      {:error, _} -> {:error, :create_failed}
    end
  end

  defp merge_event_from_external(%Event{} = existing, ext_event, account) do
    # Only update if event has changed (by etag or we don't have one)
    current_etag = get_in(existing.sync_metadata || %{}, ["etag"])
    new_etag = ext_event[:etag] || ext_event["etag"]

    if current_etag && current_etag == new_etag do
      {:ok, :skipped}
    else
      attrs = %{
        title: ext_event[:title] || ext_event["title"],
        description: ext_event[:description] || ext_event["description"],
        location: ext_event[:location] || ext_event["location"],
        starts_at: ext_event[:starts_at] || ext_event["starts_at"],
        ends_at: ext_event[:ends_at] || ext_event["ends_at"],
        all_day: ext_event[:all_day] || ext_event["all_day"] || false,
        external_id: ext_event[:external_id] || ext_event["external_id"],
        external_account_id: account.id,
        sync_status: "synced",
        last_synced_at: DateTime.utc_now(),
        sync_metadata: Map.merge(existing.sync_metadata || %{}, %{
          "etag" => new_etag,
          "source" => account.service_name
        })
      }

      # Use Ecto.Changeset directly to bypass the auto pending_push logic
      case existing
           |> Ecto.Changeset.change(attrs)
           |> Repo.update() do
        {:ok, _event} -> {:ok, :updated}
        {:error, _} -> {:error, :update_failed}
      end
    end
  end

  # ============================================================================
  # Export Events
  # ============================================================================

  defp export_events(%ExternalAccount{service_name: "google"} = account, user_id, access_token) do
    events = Events.list_events_pending_sync(user_id, account.id)

    stats =
      Enum.reduce(events, %{exported: 0, failed: 0}, fn event, acc ->
        case export_event_to_google(event, access_token, account) do
          {:ok, _} -> %{acc | exported: acc.exported + 1}
          {:error, _} -> %{acc | failed: acc.failed + 1}
        end
      end)

    {:ok, stats}
  end

  defp export_events(%ExternalAccount{service_name: "icloud_calendar"} = account, user_id, access_token) do
    case Integrations.get_refresh_token(account) do
      {:ok, apple_id} ->
        events = Events.list_events_pending_sync(user_id, account.id)

        stats =
          Enum.reduce(events, %{exported: 0, failed: 0}, fn event, acc ->
            case export_event_to_icloud(event, access_token, apple_id, account) do
              {:ok, _} -> %{acc | exported: acc.exported + 1}
              {:error, _} -> %{acc | failed: acc.failed + 1}
            end
          end)

        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp export_events(%ExternalAccount{service_name: service}, _user_id, _access_token) do
    {:error, "Unsupported calendar service: #{service}"}
  end

  defp export_event_to_google(%Event{external_id: nil} = event, access_token, account) do
    event_data = event_to_map(event)

    case Google.create_calendar_event(access_token, event_data) do
      {:ok, %{external_id: ext_id, etag: etag}} ->
        Events.update_sync_status(event, %{
          external_id: ext_id,
          external_account_id: account.id,
          sync_status: "synced",
          last_synced_at: DateTime.utc_now(),
          sync_metadata: %{"etag" => etag, "source" => "google"}
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp export_event_to_google(%Event{external_id: ext_id} = event, access_token, _account) do
    event_data = event_to_map(event)

    case Google.update_calendar_event(access_token, ext_id, event_data) do
      {:ok, %{etag: etag}} ->
        Events.update_sync_status(event, %{
          sync_status: "synced",
          last_synced_at: DateTime.utc_now(),
          sync_metadata: Map.merge(event.sync_metadata || %{}, %{"etag" => etag})
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp export_event_to_icloud(%Event{external_id: nil} = event, app_password, apple_id, account) do
    event_data = event_to_map(event)

    case ICloudCalendar.create_calendar_event(app_password, apple_id, event_data) do
      {:ok, %{external_id: ext_id}} ->
        Events.update_sync_status(event, %{
          external_id: ext_id,
          external_account_id: account.id,
          sync_status: "synced",
          last_synced_at: DateTime.utc_now(),
          sync_metadata: %{"source" => "icloud_calendar"}
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp export_event_to_icloud(%Event{external_id: ext_id} = event, app_password, apple_id, _account) do
    event_data = event_to_map(event)

    case ICloudCalendar.update_calendar_event(app_password, apple_id, ext_id, event_data) do
      {:ok, _} ->
        Events.update_sync_status(event, %{
          sync_status: "synced",
          last_synced_at: DateTime.utc_now()
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Bidirectional Sync
  # ============================================================================

  defp sync_bidirectional(account, user_id, access_token) do
    with {:ok, import_stats} <- import_events(account, user_id, access_token),
         {:ok, export_stats} <- export_events(account, user_id, access_token) do
      {:ok, Map.merge(import_stats, export_stats)}
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp event_to_map(%Event{} = event) do
    %{
      title: event.title,
      description: event.description,
      location: event.location,
      starts_at: event.starts_at,
      ends_at: event.ends_at,
      all_day: event.all_day
    }
  end

  defp broadcast_status(user_id, status, payload) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}#{user_id}", {:calendar_sync_status, status, payload})
  end

  @doc """
  Returns the PubSub topic for calendar sync events for a user.
  """
  def topic(user_id), do: "#{@topic_prefix}#{user_id}"
end
