defmodule Conezia.Workers.CalendarSyncWorkerTest do
  use Conezia.DataCase, async: true

  import Conezia.Factory

  alias Conezia.Events
  alias Conezia.Events.Event

  describe "event import deduplication" do
    test "creates new event when no match exists" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      ext_event = %{
        title: "Team Meeting",
        description: "Weekly sync",
        starts_at: ~U[2026-02-01 10:00:00Z],
        ends_at: ~U[2026-02-01 11:00:00Z],
        external_id: "google_event_123",
        etag: "etag123",
        all_day: false,
        location: nil
      }

      result = import_single_event(ext_event, user.id, account)

      assert {:ok, :created} = result

      # Verify event was created
      event = Events.find_by_external_id(user.id, "google_event_123")
      assert event
      assert event.title == "Team Meeting"
      assert event.external_account_id == account.id
      assert event.sync_status == "synced"
    end

    test "merges with existing event found by external_id" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      # Create existing event with external_id
      {:ok, existing} = Events.create_event(%{
        title: "Original Meeting",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id,
        external_id: "google_event_123",
        external_account_id: account.id,
        sync_status: "synced",
        sync_metadata: %{"etag" => "old_etag"}
      })

      # Import updated event with same external_id
      ext_event = %{
        title: "Updated Meeting Title",
        description: "New description",
        starts_at: ~U[2026-02-01 10:00:00.000000Z],
        ends_at: ~U[2026-02-01 11:00:00.000000Z],
        external_id: "google_event_123",
        etag: "new_etag",
        all_day: false,
        location: nil
      }

      result = import_single_event(ext_event, user.id, account)

      assert {:ok, :updated} = result

      # Verify event was updated
      updated = Events.find_by_external_id(user.id, "google_event_123")
      assert updated.id == existing.id
      assert updated.title == "Updated Meeting Title"
      assert updated.description == "New description"
      assert updated.sync_metadata["etag"] == "new_etag"
    end

    test "skips update when etag matches" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      # Create existing event with etag
      {:ok, _existing} = Events.create_event(%{
        title: "Unchanged Meeting",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id,
        external_id: "google_event_456",
        external_account_id: account.id,
        sync_status: "synced",
        sync_metadata: %{"etag" => "same_etag"}
      })

      # Import event with same etag
      ext_event = %{
        title: "Unchanged Meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        external_id: "google_event_456",
        etag: "same_etag",
        all_day: false
      }

      result = import_single_event(ext_event, user.id, account)

      assert {:ok, :skipped} = result
    end

    test "merges with existing event found by fuzzy title and date match" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      # Create existing local event (no external_id)
      {:ok, existing} = Events.create_event(%{
        title: "Team Standup",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id
      })

      refute existing.external_id

      # Import external event with matching title and close start time
      ext_event = %{
        title: "Team Standup",
        description: "From Google Calendar",
        starts_at: ~U[2026-02-01 10:30:00.000000Z],  # Within 1 hour tolerance
        ends_at: ~U[2026-02-01 11:00:00.000000Z],
        external_id: "google_event_789",
        etag: "etag789",
        all_day: false,
        location: nil
      }

      result = import_single_event(ext_event, user.id, account)

      assert {:ok, :updated} = result

      # Verify event was merged (now has external_id)
      merged = Events.get_event_for_user(existing.id, user.id)
      assert merged.external_id == "google_event_789"
      assert merged.external_account_id == account.id
      assert merged.sync_status == "synced"
    end

    test "does not match events outside 1 hour tolerance" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      # Create existing local event
      {:ok, _existing} = Events.create_event(%{
        title: "Morning Meeting",
        type: "meeting",
        starts_at: ~U[2026-02-01 08:00:00Z],
        user_id: user.id
      })

      # Import event with same title but 3 hours later
      ext_event = %{
        title: "Morning Meeting",
        starts_at: ~U[2026-02-01 11:00:00Z],  # Outside 1 hour tolerance
        external_id: "google_event_999",
        etag: "etag999",
        all_day: false
      }

      result = import_single_event(ext_event, user.id, account)

      # Should create new event, not merge
      assert {:ok, :created} = result

      {events, _meta} = Events.list_events(user.id)
      assert length(events) == 2
    end

    test "title matching is case-insensitive" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      # Create existing event with lowercase title
      {:ok, existing} = Events.create_event(%{
        title: "team meeting",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id
      })

      # Import event with different casing
      ext_event = %{
        title: "TEAM MEETING",
        starts_at: ~U[2026-02-01 10:00:00Z],
        external_id: "google_event_abc",
        etag: "etagabc",
        all_day: false
      }

      result = import_single_event(ext_event, user.id, account)

      assert {:ok, :updated} = result

      # Should have merged with existing
      merged = Events.get_event_for_user(existing.id, user.id)
      assert merged.external_id == "google_event_abc"
    end
  end

  describe "pending push detection" do
    test "auto-marks synced event as pending_push when updated locally" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      # Create synced event
      {:ok, event} = Events.create_event(%{
        title: "Synced Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id,
        external_id: "ext_123",
        external_account_id: account.id,
        sync_status: "synced"
      })

      assert event.sync_status == "synced"

      # Update the event locally
      {:ok, updated} = Events.update_event(event, %{title: "Modified Event"})

      assert updated.sync_status == "pending_push"
    end

    test "does not change status for local_only events" do
      user = insert(:user)

      # Create local-only event
      {:ok, event} = Events.create_event(%{
        title: "Local Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id
      })

      assert event.sync_status == "local_only"

      # Update the event
      {:ok, updated} = Events.update_event(event, %{title: "Modified Local Event"})

      # Should remain local_only
      assert updated.sync_status == "local_only"
    end
  end

  describe "list_events_pending_sync/2" do
    test "returns events with local_only status" do
      user = insert(:user)

      {:ok, local_event} = Events.create_event(%{
        title: "Local Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id,
        sync_status: "local_only"
      })

      events = Events.list_events_pending_sync(user.id)

      assert length(events) == 1
      assert hd(events).id == local_event.id
    end

    test "returns events with pending_push status" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      {:ok, pending_event} = Events.create_event(%{
        title: "Pending Push Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id,
        external_id: "ext_123",
        external_account_id: account.id,
        sync_status: "pending_push"
      })

      events = Events.list_events_pending_sync(user.id)

      assert length(events) == 1
      assert hd(events).id == pending_event.id
    end

    test "does not return synced events" do
      user = insert(:user)
      account = insert(:external_account, user: user, service_name: "google")

      {:ok, _synced_event} = Events.create_event(%{
        title: "Synced Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id,
        external_id: "ext_123",
        external_account_id: account.id,
        sync_status: "synced"
      })

      events = Events.list_events_pending_sync(user.id)

      assert events == []
    end

    test "filters by external_account_id when provided" do
      user = insert(:user)
      account1 = insert(:external_account, user: user, service_name: "google")
      account2 = insert(:external_account, user: user, service_name: "icloud_calendar")

      {:ok, event1} = Events.create_event(%{
        title: "Google Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 10:00:00Z],
        user_id: user.id,
        external_account_id: account1.id,
        sync_status: "pending_push"
      })

      {:ok, _event2} = Events.create_event(%{
        title: "iCloud Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 11:00:00Z],
        user_id: user.id,
        external_account_id: account2.id,
        sync_status: "pending_push"
      })

      {:ok, event3} = Events.create_event(%{
        title: "Unlinked Event",
        type: "meeting",
        starts_at: ~U[2026-02-01 12:00:00Z],
        user_id: user.id,
        sync_status: "local_only"
      })

      # Filter for account1 - should get Google event and unlinked event
      events = Events.list_events_pending_sync(user.id, account1.id)

      event_ids = Enum.map(events, & &1.id)
      assert event1.id in event_ids
      assert event3.id in event_ids
      assert length(events) == 2
    end
  end

  # Helper functions that replicate CalendarSyncWorker logic for testing

  defp import_single_event(ext_event, user_id, account) do
    external_id = ext_event[:external_id] || ext_event["external_id"]

    case Events.find_by_external_id(user_id, external_id) do
      nil ->
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

      case existing
           |> Ecto.Changeset.change(attrs)
           |> Conezia.Repo.update() do
        {:ok, _event} -> {:ok, :updated}
        {:error, _} -> {:error, :update_failed}
      end
    end
  end
end
