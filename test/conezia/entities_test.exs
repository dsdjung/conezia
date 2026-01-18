defmodule Conezia.EntitiesTest do
  use Conezia.DataCase, async: true

  alias Conezia.Entities
  alias Conezia.Entities.{Entity, Relationship, Identifier, Tag, Group, CustomField}

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
      attrs = %{user_id: user.id, entity_id: entity.id, type: "friend", strength: "close"}
      assert {:ok, %Relationship{}} = Entities.create_relationship(attrs)
    end

    test "create_relationship/1 with subtype creates relationship" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{user_id: user.id, entity_id: entity.id, type: "family", subtype: "spouse", strength: "close"}
      assert {:ok, %Relationship{} = rel} = Entities.create_relationship(attrs)
      assert rel.type == "family"
      assert rel.subtype == "spouse"
    end

    test "create_relationship/1 with custom_label creates relationship" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{user_id: user.id, entity_id: entity.id, type: "colleague", custom_label: "Team Lead", strength: "regular"}
      assert {:ok, %Relationship{} = rel} = Entities.create_relationship(attrs)
      assert rel.custom_label == "Team Lead"
    end

    test "update_relationship/2 updates relationship" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      relationship = insert(:relationship, user: user, entity: entity)
      assert {:ok, updated} = Entities.update_relationship(relationship, %{strength: "close"})
      assert updated.strength == "close"
    end

    test "update_relationship/2 updates subtype and custom_label" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      relationship = insert(:relationship, user: user, entity: entity, type: "friend")
      assert {:ok, updated} = Entities.update_relationship(relationship, %{
        type: "family",
        subtype: "sibling",
        custom_label: "Twin"
      })
      assert updated.type == "family"
      assert updated.subtype == "sibling"
      assert updated.custom_label == "Twin"
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

    test "get_relationships_for_entities/2 returns map of entity_id to relationship" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)
      entity3 = insert(:entity, owner: user)
      rel1 = insert(:relationship, user: user, entity: entity1, type: "friend")
      rel2 = insert(:relationship, user: user, entity: entity2, type: "family")
      # entity3 has no relationship

      relationships = Entities.get_relationships_for_entities(user.id, [entity1.id, entity2.id, entity3.id])

      assert map_size(relationships) == 2
      assert relationships[entity1.id].id == rel1.id
      assert relationships[entity1.id].type == "friend"
      assert relationships[entity2.id].id == rel2.id
      assert relationships[entity2.id].type == "family"
      assert is_nil(relationships[entity3.id])
    end
  end

  describe "relationship subtypes" do
    test "valid family subtypes" do
      valid_subtypes = Relationship.subtypes_for_type("family")
      assert "spouse" in valid_subtypes
      assert "child" in valid_subtypes
      assert "parent" in valid_subtypes
      assert "sibling" in valid_subtypes
    end

    test "valid colleague subtypes" do
      valid_subtypes = Relationship.subtypes_for_type("colleague")
      assert "coworker" in valid_subtypes
      assert "manager" in valid_subtypes
      assert "direct_report" in valid_subtypes
    end

    test "valid professional subtypes" do
      valid_subtypes = Relationship.subtypes_for_type("professional")
      assert "client" in valid_subtypes
      assert "vendor" in valid_subtypes
      assert "consultant" in valid_subtypes
    end

    test "display_label returns custom_label when present" do
      relationship = %Relationship{type: "friend", subtype: nil, custom_label: "Best Friend"}
      assert Relationship.display_label(relationship) == "Best Friend"
    end

    test "display_label returns subtype when no custom_label" do
      relationship = %Relationship{type: "family", subtype: "spouse", custom_label: nil}
      assert Relationship.display_label(relationship) == "Spouse"
    end

    test "display_label returns type when no subtype or custom_label" do
      relationship = %Relationship{type: "friend", subtype: nil, custom_label: nil}
      assert Relationship.display_label(relationship) == "Friend"
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
      attrs = %{name: "important", color: "red", user_id: user.id}
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

  describe "custom_fields" do
    test "create_custom_field/1 creates text field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{
        entity_id: entity.id,
        field_type: "text",
        category: "personal",
        name: "Nickname",
        key: "nickname",
        value: "Bobby"
      }
      assert {:ok, %CustomField{} = field} = Entities.create_custom_field(attrs)
      assert field.name == "Nickname"
      assert field.value == "Bobby"
      assert field.field_type == "text"
    end

    test "create_custom_field/1 creates date field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{
        entity_id: entity.id,
        field_type: "date",
        category: "important_dates",
        name: "Birthday",
        key: "birthday",
        date_value: ~D[1990-05-15],
        is_recurring: true
      }
      assert {:ok, %CustomField{} = field} = Entities.create_custom_field(attrs)
      assert field.date_value == ~D[1990-05-15]
      assert field.is_recurring == true
    end

    test "create_custom_field/1 creates number field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{
        entity_id: entity.id,
        field_type: "number",
        category: "other",
        name: "Shoe Size",
        key: "shoe_size",
        number_value: Decimal.new("10.5")
      }
      assert {:ok, %CustomField{} = field} = Entities.create_custom_field(attrs)
      assert Decimal.equal?(field.number_value, Decimal.new("10.5"))
    end

    test "create_custom_field/1 creates boolean field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{
        entity_id: entity.id,
        field_type: "boolean",
        category: "preferences",
        name: "Prefers Text",
        key: "prefers_text",
        boolean_value: true
      }
      assert {:ok, %CustomField{} = field} = Entities.create_custom_field(attrs)
      assert field.boolean_value == true
    end

    test "list_custom_fields/1 returns fields for entity" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, _} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "personal", name: "Nick", key: "nick", value: "Bobby"})
      {:ok, _} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "date", category: "important_dates", name: "Birthday", key: "birthday", date_value: ~D[1990-01-01]})

      fields = Entities.list_custom_fields(entity.id)
      assert length(fields) == 2
    end

    test "list_custom_fields/2 filters by category" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, _} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "personal", name: "Nick", key: "nick", value: "Bobby"})
      {:ok, _} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "date", category: "important_dates", name: "Birthday", key: "birthday", date_value: ~D[1990-01-01]})

      fields = Entities.list_custom_fields(entity.id, category: "important_dates")
      assert length(fields) == 1
      assert hd(fields).name == "Birthday"
    end

    test "update_custom_field/2 updates field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, field} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "personal", name: "Nick", key: "nick", value: "Bobby"})

      assert {:ok, updated} = Entities.update_custom_field(field, %{value: "Bob"})
      assert updated.value == "Bob"
    end

    test "delete_custom_field/1 deletes field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, field} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "personal", name: "Nick", key: "nick", value: "Bobby"})

      assert {:ok, _} = Entities.delete_custom_field(field)
      assert is_nil(Entities.get_custom_field(field.id))
    end

    test "get_custom_field_by_key/2 returns field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, _} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "personal", name: "Nick", key: "nickname", value: "Bobby"})

      field = Entities.get_custom_field_by_key(entity.id, "nickname")
      assert field.value == "Bobby"
    end

    test "set_custom_field/4 creates new field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      assert {:ok, field} = Entities.set_custom_field(entity.id, "company", "Acme Inc", category: "work")
      assert field.value == "Acme Inc"
      assert field.category == "work"
    end

    test "set_custom_field/4 updates existing field" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, _} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "work", name: "Company", key: "company", value: "Old Corp"})

      assert {:ok, field} = Entities.set_custom_field(entity.id, "company", "New Inc")
      assert field.value == "New Inc"

      # Should still only have one field with that key
      fields = Entities.list_custom_fields(entity.id)
      company_fields = Enum.filter(fields, & &1.key == "company")
      assert length(company_fields) == 1
    end

    test "unique constraint on entity_id + key" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, _} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "personal", name: "Nick", key: "nick", value: "Bobby"})

      # Attempting to create another field with the same entity_id + key should fail
      assert {:error, changeset} = Entities.create_custom_field(%{entity_id: entity.id, field_type: "text", category: "personal", name: "Nickname", key: "nick", value: "Robert"})
      # The unique constraint violation shows on entity_id since that's the first field in the composite key
      assert changeset.errors != []
    end

    test "predefined_custom_fields/0 returns predefined fields" do
      fields = Entities.predefined_custom_fields()
      assert is_list(fields)
      assert Enum.any?(fields, fn f -> f.key == "birthday" end)
      assert Enum.any?(fields, fn f -> f.key == "company" end)
    end
  end
end
