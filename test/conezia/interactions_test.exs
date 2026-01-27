defmodule Conezia.InteractionsTest do
  use Conezia.DataCase, async: true

  alias Conezia.Interactions
  alias Conezia.Interactions.Interaction

  import Conezia.Factory

  describe "interactions" do
    test "get_interaction/1 returns interaction" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      interaction = insert(:interaction, user: user, entity: entity)

      assert %Interaction{} = Interactions.get_interaction(interaction.id)
    end

    test "get_interaction_for_user/2 returns user's interaction" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      interaction = insert(:interaction, user: user, entity: entity)

      assert %Interaction{} = Interactions.get_interaction_for_user(interaction.id, user.id)
    end

    test "list_interactions/2 returns user's interactions" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:interaction, user: user, entity: entity)
      insert(:interaction, user: user, entity: entity)

      interactions = Interactions.list_interactions(user.id)
      assert length(interactions) == 2
    end

    test "list_interactions/2 filters by entity_id" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)
      insert(:interaction, user: user, entity: entity1)
      insert(:interaction, user: user, entity: entity2)

      interactions = Interactions.list_interactions(user.id, entity_id: entity1.id)
      assert length(interactions) == 1
    end

    test "list_interactions/2 filters by type" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:interaction, user: user, entity: entity, type: "meeting")
      insert(:interaction, user: user, entity: entity, type: "call")

      interactions = Interactions.list_interactions(user.id, type: "meeting")
      assert length(interactions) == 1
    end

    test "create_interaction/1 creates interaction" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{
        type: "call",
        content: "Discussed project updates",
        user_id: user.id,
        entity_id: entity.id
      }

      assert {:ok, %Interaction{}} = Interactions.create_interaction(attrs)
    end

    test "get_last_event_for_entity/2 returns most recent meeting or call" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      old_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      recent_time = DateTime.utc_now()

      # Create an email (should not be returned)
      _email = insert(:interaction, user: user, entity: entity, type: "email", occurred_at: recent_time)
      # Create an old call
      _old_call = insert(:interaction, user: user, entity: entity, type: "call", occurred_at: old_time)
      # Create a recent meeting (should be returned)
      recent_meeting = insert(:interaction, user: user, entity: entity, type: "meeting", occurred_at: recent_time)

      result = Interactions.get_last_event_for_entity(entity.id, user.id)
      assert result.id == recent_meeting.id
    end

    test "get_last_event_for_entity/2 returns nil when no meetings or calls" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      # Create only an email (not a meeting or call)
      insert(:interaction, user: user, entity: entity, type: "email")

      assert is_nil(Interactions.get_last_event_for_entity(entity.id, user.id))
    end

    test "get_last_event_for_entity/2 returns nil for different user" do
      user1 = insert(:user)
      user2 = insert(:user)
      entity = insert(:entity, owner: user1)
      insert(:interaction, user: user1, entity: entity, type: "meeting")

      # user2 should not see user1's interactions
      assert is_nil(Interactions.get_last_event_for_entity(entity.id, user2.id))
    end
  end
end
