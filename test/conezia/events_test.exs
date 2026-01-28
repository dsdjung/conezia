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
end
