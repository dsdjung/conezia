defmodule Conezia.EventsTest do
  use Conezia.DataCase

  import Conezia.Factory

  alias Conezia.Events
  alias Conezia.Events.Event

  describe "create_event/1" do
    test "creates event with valid attrs" do
      user = insert(:user)

      attrs = %{
        title: "Birthday Party",
        type: "birthday",
        starts_at: DateTime.add(DateTime.utc_now(), 86400 * 30, :second),
        all_day: true,
        user_id: user.id
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      assert event.title == "Birthday Party"
      assert event.type == "birthday"
      assert event.all_day == true
    end

    test "fails with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event(%{})
    end

    test "validates event type" do
      user = insert(:user)

      attrs = %{
        title: "Test",
        type: "invalid_type",
        starts_at: DateTime.utc_now(),
        user_id: user.id
      }

      assert {:error, changeset} = Events.create_event(attrs)
      assert errors_on(changeset).type
    end

    test "validates end time is after start time" do
      user = insert(:user)
      now = DateTime.utc_now()

      attrs = %{
        title: "Test",
        type: "meeting",
        starts_at: now,
        ends_at: DateTime.add(now, -3600, :second),
        user_id: user.id
      }

      assert {:error, changeset} = Events.create_event(attrs)
      assert errors_on(changeset).ends_at
    end

    test "creates auto-reminder for future events" do
      user = insert(:user)

      attrs = %{
        title: "Future Party",
        type: "party",
        starts_at: DateTime.add(DateTime.utc_now(), 86400 * 30, :second),
        user_id: user.id
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      assert event.reminder_id
    end

    test "does not create reminder for past events" do
      user = insert(:user)

      attrs = %{
        title: "Past Event",
        type: "meeting",
        starts_at: DateTime.add(DateTime.utc_now(), -86400, :second),
        user_id: user.id
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      refute event.reminder_id
    end

    test "creates yearly recurring reminder when remind_yearly is true" do
      user = insert(:user)

      attrs = %{
        title: "Wedding Day",
        type: "wedding",
        starts_at: DateTime.add(DateTime.utc_now(), 86400 * 30, :second),
        remind_yearly: true,
        user_id: user.id
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      assert event.reminder_id
      assert event.remind_yearly == true
      refute event.is_recurring

      reminder = Conezia.Reminders.get_reminder(event.reminder_id)
      assert reminder.recurrence_rule == %{"freq" => "yearly"}
    end

    test "accepts wedding and memorial event types" do
      user = insert(:user)

      for type <- ["wedding", "memorial"] do
        attrs = %{
          title: "Test #{type}",
          type: type,
          starts_at: DateTime.utc_now(),
          user_id: user.id
        }

        assert {:ok, %Event{}} = Events.create_event(attrs)
      end
    end

    test "links entities when entity_ids provided" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      attrs = %{
        title: "Wedding Anniversary",
        type: "anniversary",
        starts_at: DateTime.add(DateTime.utc_now(), 86400 * 30, :second),
        all_day: true,
        is_recurring: true,
        recurrence_rule: %{"freq" => "yearly"},
        user_id: user.id,
        entity_ids: [entity1.id, entity2.id]
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      assert length(event.entities) == 2
      entity_ids = Enum.map(event.entities, & &1.id) |> Enum.sort()
      assert entity_ids == Enum.sort([entity1.id, entity2.id])
    end

    test "encrypts sensitive fields" do
      user = insert(:user)

      attrs = %{
        title: "Secret Meeting",
        type: "meeting",
        description: "Very private",
        location: "123 Main St",
        notes: "Bring documents",
        starts_at: DateTime.utc_now(),
        user_id: user.id
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      assert event.title_encrypted
      assert event.description_encrypted
      assert event.location_encrypted
      assert event.notes_encrypted
    end

    test "creates event with location coordinates" do
      user = insert(:user)

      attrs = %{
        title: "Office Meeting",
        type: "meeting",
        starts_at: DateTime.utc_now(),
        location: "1600 Amphitheatre Parkway, Mountain View, CA",
        place_id: "ChIJj61dQgK6j4AR4GeTYWZsKWw",
        latitude: 37.4220656,
        longitude: -122.0840897,
        user_id: user.id
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      assert event.place_id == "ChIJj61dQgK6j4AR4GeTYWZsKWw"
      assert_in_delta event.latitude, 37.4220656, 0.0001
      assert_in_delta event.longitude, -122.0840897, 0.0001
    end
  end

  describe "list_events/2" do
    test "lists events for user" do
      user = insert(:user)
      insert(:event, user: user)
      insert(:event, user: user)

      {events, meta} = Events.list_events(user.id)
      assert length(events) == 2
      assert is_boolean(meta.has_more)
    end

    test "does not return other users' events" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:event, user: user1)
      insert(:event, user: user2)

      {events, _meta} = Events.list_events(user1.id)
      assert length(events) == 1
    end

    test "filters by type" do
      user = insert(:user)
      insert(:event, user: user, type: "meeting")
      insert(:event, user: user, type: "dinner")

      {events, _meta} = Events.list_events(user.id, type: "meeting")
      assert length(events) == 1
      assert hd(events).type == "meeting"
    end

    test "filters by search term" do
      user = insert(:user)
      insert(:event, user: user, title: "Birthday Party")
      insert(:event, user: user, title: "Team Meeting")

      {events, _meta} = Events.list_events(user.id, search: "birthday")
      assert length(events) == 1
      assert hd(events).title == "Birthday Party"
    end

    test "search is case-insensitive" do
      user = insert(:user)
      insert(:event, user: user, title: "Birthday Party")

      {events, _meta} = Events.list_events(user.id, search: "BIRTHDAY")
      assert length(events) == 1
    end

    test "sorts by date descending" do
      user = insert(:user)
      early = insert(:event, user: user, starts_at: ~U[2026-01-01 00:00:00Z])
      late = insert(:event, user: user, starts_at: ~U[2026-06-01 00:00:00Z])

      {events, _meta} = Events.list_events(user.id, sort: "date_desc")
      assert hd(events).id == late.id
      assert List.last(events).id == early.id
    end

    test "sorts by title" do
      user = insert(:user)
      insert(:event, user: user, title: "Zebra Event")
      insert(:event, user: user, title: "Alpha Event")

      {events, _meta} = Events.list_events(user.id, sort: "title")
      assert hd(events).title == "Alpha Event"
      assert List.last(events).title == "Zebra Event"
    end

    test "has_more is true when more events exist" do
      user = insert(:user)
      for _ <- 1..3, do: insert(:event, user: user)

      {events, meta} = Events.list_events(user.id, limit: 2)
      assert length(events) == 2
      assert meta.has_more == true
    end

    test "has_more is false when no more events" do
      user = insert(:user)
      insert(:event, user: user)

      {events, meta} = Events.list_events(user.id, limit: 10)
      assert length(events) == 1
      assert meta.has_more == false
    end

    test "filters by entity_id" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      event = insert(:event, user: user)
      insert(:event, user: user)

      Events.add_entity_to_event(event.id, entity.id)

      {events, _meta} = Events.list_events(user.id, entity_id: entity.id)
      assert length(events) == 1
      assert hd(events).id == event.id
    end
  end

  describe "count_events/2" do
    test "counts all events for user" do
      user = insert(:user)
      insert(:event, user: user)
      insert(:event, user: user)
      insert(:event, user: insert(:user))

      assert Events.count_events(user.id) == 2
    end

    test "counts with search filter" do
      user = insert(:user)
      insert(:event, user: user, title: "Birthday Party")
      insert(:event, user: user, title: "Team Meeting")

      assert Events.count_events(user.id, search: "birthday") == 1
    end

    test "counts with type filter" do
      user = insert(:user)
      insert(:event, user: user, type: "meeting")
      insert(:event, user: user, type: "dinner")

      assert Events.count_events(user.id, type: "meeting") == 1
    end

    test "counts with entity_id filter" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      event = insert(:event, user: user)
      insert(:event, user: user)

      Events.add_entity_to_event(event.id, entity.id)

      assert Events.count_events(user.id, entity_id: entity.id) == 1
    end
  end

  describe "upcoming_events/2" do
    test "returns events in next N days" do
      user = insert(:user)
      insert(:event, user: user, starts_at: DateTime.add(DateTime.utc_now(), 86400 * 5, :second))
      insert(:event, user: user, starts_at: DateTime.add(DateTime.utc_now(), 86400 * 60, :second))

      events = Events.upcoming_events(user.id, 30)
      assert length(events) == 1
    end

    test "excludes past events" do
      user = insert(:user)
      insert(:event, user: user, starts_at: DateTime.add(DateTime.utc_now(), -86400, :second))

      events = Events.upcoming_events(user.id)
      assert events == []
    end
  end

  describe "update_event/2" do
    test "updates event with valid attrs" do
      user = insert(:user)
      event = insert(:event, user: user)

      assert {:ok, updated} = Events.update_event(event, %{title: "Updated Title"})
      assert updated.title == "Updated Title"
    end

    test "updates entity links" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)
      event = insert(:event, user: user)

      Events.add_entity_to_event(event.id, entity1.id)

      assert {:ok, updated} = Events.update_event(event, %{entity_ids: [entity2.id]})
      assert length(updated.entities) == 1
      assert hd(updated.entities).id == entity2.id
    end
  end

  describe "delete_event/1" do
    test "deletes event" do
      user = insert(:user)
      event = insert(:event, user: user)

      assert {:ok, _} = Events.delete_event(event)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(event.id) end
    end

    test "deletes linked reminder" do
      user = insert(:user)

      {:ok, event} = Events.create_event(%{
        title: "Future Event",
        type: "party",
        starts_at: DateTime.add(DateTime.utc_now(), 86400 * 30, :second),
        user_id: user.id
      })

      reminder_id = event.reminder_id
      assert reminder_id

      {:ok, _} = Events.delete_event(event)
      assert Conezia.Reminders.get_reminder(reminder_id) == nil
    end
  end

  describe "entity linking" do
    test "add_entity_to_event/3 links entity with role" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      event = insert(:event, user: user)

      assert {:ok, ee} = Events.add_entity_to_event(event.id, entity.id, "host")
      assert ee.role == "host"
    end

    test "add_entity_to_event/3 prevents duplicates" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      event = insert(:event, user: user)

      assert {:ok, _} = Events.add_entity_to_event(event.id, entity.id)
      assert {:error, _} = Events.add_entity_to_event(event.id, entity.id)
    end

    test "remove_entity_from_event/2 removes the link" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      event = insert(:event, user: user)

      Events.add_entity_to_event(event.id, entity.id)
      assert {1, _} = Events.remove_entity_from_event(event.id, entity.id)

      events = Events.list_events_for_entity(entity.id, user.id)
      assert events == []
    end

    test "list_events_for_entity/3 returns entity's events" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      event = insert(:event, user: user)
      insert(:event, user: user)

      Events.add_entity_to_event(event.id, entity.id)

      events = Events.list_events_for_entity(entity.id, user.id)
      assert length(events) == 1
      assert hd(events).id == event.id
    end
  end

  describe "get_event_for_user/2" do
    test "returns event for correct user" do
      user = insert(:user)
      event = insert(:event, user: user)

      assert %Event{} = Events.get_event_for_user(event.id, user.id)
    end

    test "returns nil for wrong user" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event, user: user1)

      assert Events.get_event_for_user(event.id, user2.id) == nil
    end
  end

  describe "find_by_external_id/2" do
    test "returns event with matching external_id" do
        user = insert(:user)
        account = insert(:external_account, user: user, service_name: "google")

        {:ok, event} = Events.create_event(%{
          title: "Synced Event",
          type: "meeting",
          starts_at: DateTime.utc_now(),
          user_id: user.id,
          external_id: "google_123",
          external_account_id: account.id
        })

        found = Events.find_by_external_id(user.id, "google_123")
        assert found.id == event.id
      end

      test "returns nil for non-existent external_id" do
        user = insert(:user)
        assert Events.find_by_external_id(user.id, "nonexistent") == nil
      end

      test "does not return events from other users" do
        user1 = insert(:user)
        user2 = insert(:user)
        account = insert(:external_account, user: user1, service_name: "google")

        {:ok, _event} = Events.create_event(%{
          title: "User1 Event",
          type: "meeting",
          starts_at: DateTime.utc_now(),
          user_id: user1.id,
          external_id: "google_123",
          external_account_id: account.id
        })

        assert Events.find_by_external_id(user2.id, "google_123") == nil
    end
  end

  describe "find_matching_event/2" do
    test "finds event with exact title and matching time" do
        user = insert(:user)
        base_time = ~U[2026-02-01 10:00:00Z]

        {:ok, event} = Events.create_event(%{
          title: "Team Meeting",
          type: "meeting",
          starts_at: base_time,
          user_id: user.id
        })

        found = Events.find_matching_event(user.id, %{title: "Team Meeting", starts_at: base_time})
        assert found.id == event.id
      end

      test "finds event within 1 hour tolerance" do
        user = insert(:user)
        base_time = ~U[2026-02-01 10:00:00Z]

        {:ok, event} = Events.create_event(%{
          title: "Team Meeting",
          type: "meeting",
          starts_at: base_time,
          user_id: user.id
        })

        # 30 minutes later - should match
        search_time = DateTime.add(base_time, 1800, :second)
        found = Events.find_matching_event(user.id, %{title: "Team Meeting", starts_at: search_time})
        assert found.id == event.id

        # 30 minutes earlier - should match
        search_time = DateTime.add(base_time, -1800, :second)
        found = Events.find_matching_event(user.id, %{title: "Team Meeting", starts_at: search_time})
        assert found.id == event.id
      end

      test "does not find event outside 1 hour tolerance" do
        user = insert(:user)
        base_time = ~U[2026-02-01 10:00:00Z]

        {:ok, _event} = Events.create_event(%{
          title: "Team Meeting",
          type: "meeting",
          starts_at: base_time,
          user_id: user.id
        })

        # 2 hours later - should not match
        search_time = DateTime.add(base_time, 7200, :second)
        assert Events.find_matching_event(user.id, %{title: "Team Meeting", starts_at: search_time}) == nil
      end

      test "title matching is case-insensitive" do
        user = insert(:user)
        base_time = ~U[2026-02-01 10:00:00Z]

        {:ok, event} = Events.create_event(%{
          title: "Team Meeting",
          type: "meeting",
          starts_at: base_time,
          user_id: user.id
        })

        found = Events.find_matching_event(user.id, %{title: "TEAM MEETING", starts_at: base_time})
        assert found.id == event.id

        found = Events.find_matching_event(user.id, %{title: "team meeting", starts_at: base_time})
        assert found.id == event.id
      end

      test "trims whitespace when matching titles" do
        user = insert(:user)
        base_time = ~U[2026-02-01 10:00:00Z]

        {:ok, event} = Events.create_event(%{
          title: "Team Meeting",
          type: "meeting",
          starts_at: base_time,
          user_id: user.id
        })

        found = Events.find_matching_event(user.id, %{title: "  Team Meeting  ", starts_at: base_time})
        assert found.id == event.id
      end

      test "does not match events from other users" do
        user1 = insert(:user)
        user2 = insert(:user)
        base_time = ~U[2026-02-01 10:00:00Z]

        {:ok, _event} = Events.create_event(%{
          title: "Team Meeting",
          type: "meeting",
          starts_at: base_time,
          user_id: user1.id
        })

        assert Events.find_matching_event(user2.id, %{title: "Team Meeting", starts_at: base_time}) == nil
    end
  end

  describe "update_sync_status/2" do
    test "updates sync fields" do
        user = insert(:user)

        {:ok, event} = Events.create_event(%{
          title: "Local Event",
          type: "meeting",
          starts_at: DateTime.utc_now(),
          user_id: user.id
        })

        assert event.sync_status == "local_only"
        assert event.external_id == nil

        now = DateTime.utc_now()
        {:ok, updated} = Events.update_sync_status(event, %{
          external_id: "ext_123",
          sync_status: "synced",
          last_synced_at: now,
          sync_metadata: %{"etag" => "abc123"}
        })

        assert updated.external_id == "ext_123"
        assert updated.sync_status == "synced"
        assert updated.last_synced_at == now
        assert updated.sync_metadata == %{"etag" => "abc123"}
    end
  end

  describe "mark_pending_push/1" do
    test "marks synced event as pending_push" do
        user = insert(:user)
        account = insert(:external_account, user: user, service_name: "google")

        {:ok, event} = Events.create_event(%{
          title: "Synced Event",
          type: "meeting",
          starts_at: DateTime.utc_now(),
          user_id: user.id,
          external_id: "ext_123",
          external_account_id: account.id,
          sync_status: "synced"
        })

        {:ok, marked} = Events.mark_pending_push(event)
        assert marked.sync_status == "pending_push"
      end

      test "returns unchanged event when no external_id" do
        user = insert(:user)

        {:ok, event} = Events.create_event(%{
          title: "Local Event",
          type: "meeting",
          starts_at: DateTime.utc_now(),
          user_id: user.id
        })

        {:ok, result} = Events.mark_pending_push(event)
        assert result.id == event.id
        assert result.sync_status == "local_only"
    end
  end

  describe "sync_status validation" do
    test "accepts valid sync statuses" do
        user = insert(:user)

        for status <- ~w(local_only synced pending_push pending_pull conflict) do
          {:ok, event} = Events.create_event(%{
            title: "Event with #{status}",
            type: "meeting",
            starts_at: DateTime.utc_now(),
            user_id: user.id,
            sync_status: status
          })

          assert event.sync_status == status
        end
      end

      test "rejects invalid sync status" do
        user = insert(:user)

        {:error, changeset} = Events.create_event(%{
          title: "Invalid Status Event",
          type: "meeting",
          starts_at: DateTime.utc_now(),
          user_id: user.id,
          sync_status: "invalid_status"
        })

        assert errors_on(changeset).sync_status
    end
  end
end
