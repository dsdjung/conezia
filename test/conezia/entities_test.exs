defmodule Conezia.EntitiesTest do
  use Conezia.DataCase, async: true

  alias Conezia.Entities
  alias Conezia.Entities.{Entity, Relationship, Identifier, Tag, Group}

  import Conezia.Factory

  describe "entities" do
    test "get_entity/1 returns entity" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      assert %Entity{} = Entities.get_entity(entity.id)
    end

    test "get_entity_for_user/2 returns entity for owner" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      assert %Entity{} = Entities.get_entity_for_user(entity.id, user.id)
    end

    test "get_entity_for_user/2 returns nil for non-owner" do
      user = insert(:user)
      other_user = insert(:user)
      entity = insert(:entity, owner: user)
      assert is_nil(Entities.get_entity_for_user(entity.id, other_user.id))
    end

    test "list_entities/2 returns user's entities" do
      user = insert(:user)
      insert(:entity, owner: user)
      insert(:entity, owner: user)
      other_user = insert(:user)
      insert(:entity, owner: other_user)

      entities = Entities.list_entities(user.id)
      assert length(entities) == 2
    end

    test "list_entities/2 filters by type" do
      user = insert(:user)
      insert(:entity, owner: user, type: "person")
      insert(:entity, owner: user, type: "organization")

      entities = Entities.list_entities(user.id, type: "person")
      assert length(entities) == 1
      assert hd(entities).type == "person"
    end

    test "create_entity/1 creates entity" do
      user = insert(:user)
      attrs = %{name: "Test Entity", type: "person", owner_id: user.id}
      assert {:ok, %Entity{} = entity} = Entities.create_entity(attrs)
      assert entity.name == "Test Entity"
    end

    test "update_entity/2 updates entity" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      assert {:ok, updated} = Entities.update_entity(entity, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "archive_entity/1 sets archived_at" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      assert {:ok, archived} = Entities.archive_entity(entity)
      assert archived.archived_at
    end

    test "unarchive_entity/1 clears archived_at" do
      user = insert(:user)
      entity = insert(:entity, owner: user, archived_at: DateTime.utc_now())
      assert {:ok, unarchived} = Entities.unarchive_entity(entity)
      assert is_nil(unarchived.archived_at)
    end

    test "delete_entity/1 deletes entity" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      assert {:ok, %Entity{}} = Entities.delete_entity(entity)
      assert is_nil(Entities.get_entity(entity.id))
    end

    test "count_user_entities/1 returns count" do
      user = insert(:user)
      insert(:entity, owner: user)
      insert(:entity, owner: user)
      insert(:entity, owner: user, archived_at: DateTime.utc_now())

      assert Entities.count_user_entities(user.id) == 2
    end
  end

  describe "relationships" do
    test "create_relationship/1 creates relationship" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{user_id: user.id, entity_id: entity.id, type: "friend", strength: 75}
      assert {:ok, %Relationship{}} = Entities.create_relationship(attrs)
    end

    test "update_relationship/2 updates relationship" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      relationship = insert(:relationship, user: user, entity: entity)
      assert {:ok, updated} = Entities.update_relationship(relationship, %{strength: 90})
      assert updated.strength == 90
    end

    test "list_relationships/2 returns user relationships" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)
      insert(:relationship, user: user, entity: entity1)
      insert(:relationship, user: user, entity: entity2)

      relationships = Entities.list_relationships(user.id)
      assert length(relationships) == 2
    end
  end

  describe "identifiers" do
    test "create_identifier/1 creates identifier" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{type: "email", value: "test@example.com", entity_id: entity.id}
      assert {:ok, %Identifier{}} = Entities.create_identifier(attrs)
    end

    test "list_identifiers_for_entity/1 returns identifiers" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:identifier, entity: entity, type: "email")
      insert(:identifier, entity: entity, type: "phone")

      identifiers = Entities.list_identifiers_for_entity(entity.id)
      assert length(identifiers) == 2
    end

    test "check_identifier_duplicates/2 finds duplicates" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:identifier, entity: entity, type: "email", value: "test@example.com")

      duplicates = Entities.check_identifier_duplicates("email", "test@example.com")
      assert length(duplicates) == 1
    end
  end

  describe "tags" do
    test "create_tag/1 creates tag" do
      user = insert(:user)
      attrs = %{name: "important", color: "#FF0000", user_id: user.id}
      assert {:ok, %Tag{}} = Entities.create_tag(attrs)
    end

    test "list_tags/1 returns user tags" do
      user = insert(:user)
      insert(:tag, user: user)
      insert(:tag, user: user)

      tags = Entities.list_tags(user.id)
      assert length(tags) == 2
    end

    test "add_tags_to_entity/2 adds tags" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      tag1 = insert(:tag, user: user)
      tag2 = insert(:tag, user: user)

      assert {:ok, _entity} = Entities.add_tags_to_entity(entity, [tag1.id, tag2.id])
    end

    test "add_tags_to_entity/2 fails with empty list" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      assert {:error, "No tag IDs provided"} = Entities.add_tags_to_entity(entity, [])
    end

    test "remove_tag_from_entity/2 removes tag" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      tag = insert(:tag, user: user)
      {:ok, _} = Entities.add_tags_to_entity(entity, [tag.id])

      assert {:ok, _entity} = Entities.remove_tag_from_entity(entity, tag.id)
    end
  end

  describe "groups" do
    test "create_group/1 creates group" do
      user = insert(:user)
      attrs = %{name: "Friends", user_id: user.id}
      assert {:ok, %Group{}} = Entities.create_group(attrs)
    end

    test "list_groups/1 returns user groups" do
      user = insert(:user)
      insert(:group, user: user)
      insert(:group, user: user)

      groups = Entities.list_groups(user.id)
      assert length(groups) == 2
    end

    test "add_entities_to_group/2 adds entities to static group" do
      user = insert(:user)
      group = insert(:group, user: user, is_smart: false)
      entity = insert(:entity, owner: user)

      assert {:ok, _group} = Entities.add_entities_to_group(group, [entity.id])
    end

    test "add_entities_to_group/2 fails for smart group" do
      user = insert(:user)
      group = insert(:group, user: user, is_smart: true)
      entity = insert(:entity, owner: user)

      assert {:error, :cannot_add_to_smart_group} = Entities.add_entities_to_group(group, [entity.id])
    end

    test "list_group_members/2 returns members" do
      user = insert(:user)
      group = insert(:group, user: user, is_smart: false)
      entity = insert(:entity, owner: user)
      {:ok, _} = Entities.add_entities_to_group(group, [entity.id])

      {members, _meta} = Entities.list_group_members(group, limit: 50)
      assert length(members) == 1
    end
  end
end
