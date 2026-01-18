defmodule Conezia.RemindersTest do
  use Conezia.DataCase, async: true

  alias Conezia.Reminders
  alias Conezia.Reminders.Reminder

  import Conezia.Factory

  describe "reminders" do
    test "get_reminder/1 returns reminder" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity)
      assert %Reminder{} = Reminders.get_reminder(reminder.id)
    end

    test "get_reminder_for_user/2 returns user's reminder" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity)
      assert %Reminder{} = Reminders.get_reminder_for_user(reminder.id, user.id)
    end

    test "get_reminder_for_user/2 returns nil for other user" do
      user = insert(:user)
      other_user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity)
      assert is_nil(Reminders.get_reminder_for_user(reminder.id, other_user.id))
    end

    test "list_reminders/2 returns user's reminders" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:reminder, user: user, entity: entity)
      insert(:reminder, user: user, entity: entity)

      {reminders, _meta} = Reminders.list_reminders(user.id)
      assert length(reminders) == 2
    end

    test "list_reminders/2 filters by status" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:reminder, user: user, entity: entity, completed_at: nil)
      insert(:reminder, user: user, entity: entity, completed_at: DateTime.utc_now())

      {pending, _} = Reminders.list_reminders(user.id, status: "pending")
      assert length(pending) == 1

      {completed, _} = Reminders.list_reminders(user.id, status: "completed")
      assert length(completed) == 1
    end

    test "create_reminder/1 creates reminder" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{
        title: "Follow up",
        type: "follow_up",
        due_at: DateTime.add(DateTime.utc_now(), 86400, :second),
        user_id: user.id,
        entity_id: entity.id
      }

      assert {:ok, %Reminder{}} = Reminders.create_reminder(attrs)
    end

    test "update_reminder/2 updates reminder" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity)

      assert {:ok, updated} = Reminders.update_reminder(reminder, %{title: "Updated Title"})
      assert updated.title == "Updated Title"
    end

    test "delete_reminder/1 deletes reminder" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity)

      assert {:ok, %Reminder{}} = Reminders.delete_reminder(reminder)
      assert is_nil(Reminders.get_reminder(reminder.id))
    end

    test "complete_reminder/1 marks reminder complete" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity, completed_at: nil)

      assert {:ok, completed} = Reminders.complete_reminder(reminder)
      assert completed.completed_at
    end

    test "snooze_reminder/2 sets snoozed_until" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity)
      snooze_until = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert {:ok, snoozed} = Reminders.snooze_reminder(reminder, snooze_until)
      assert snoozed.snoozed_until
    end

    test "snooze_reminder_by_duration/2 calculates snooze time" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      reminder = insert(:reminder, user: user, entity: entity)

      assert {:ok, snoozed} = Reminders.snooze_reminder_by_duration(reminder, "1_hour")
      assert snoozed.snoozed_until
    end

    test "list_due_reminders/1 returns due reminders" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      past_due = DateTime.add(DateTime.utc_now(), -3600, :second)
      future = DateTime.add(DateTime.utc_now(), 86400, :second)

      insert(:reminder, user: user, entity: entity, due_at: past_due, completed_at: nil)
      insert(:reminder, user: user, entity: entity, due_at: future, completed_at: nil)

      reminders = Reminders.list_due_reminders()
      assert length(reminders) == 1
    end
  end
end
