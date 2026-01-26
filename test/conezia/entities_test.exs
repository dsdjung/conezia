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

      {entities, _meta} = Entities.list_entities(user.id)
      assert length(entities) == 2
    end

    test "list_entities/2 filters by type" do
      user = insert(:user)
      insert(:entity, owner: user, type: "person")
      insert(:entity, owner: user, type: "organization")

      {entities, _meta} = Entities.list_entities(user.id, type: "person")
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

  describe "entity lookup functions" do
    test "find_by_email/2 finds entity by email (case-insensitive)" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:identifier, entity: entity, type: "email", value: "test@example.com")

      # Should find with exact case
      assert %Entity{} = Entities.find_by_email(user.id, "test@example.com")

      # Should find with different case
      assert %Entity{} = Entities.find_by_email(user.id, "TEST@EXAMPLE.COM")
      assert %Entity{} = Entities.find_by_email(user.id, "Test@Example.Com")

      # Should not find non-existent email
      assert is_nil(Entities.find_by_email(user.id, "other@example.com"))
    end

    test "find_by_email/2 does not return other users' entities" do
      user1 = insert(:user)
      user2 = insert(:user)
      entity = insert(:entity, owner: user1)
      insert(:identifier, entity: entity, type: "email", value: "test@example.com")

      assert %Entity{} = Entities.find_by_email(user1.id, "test@example.com")
      assert is_nil(Entities.find_by_email(user2.id, "test@example.com"))
    end

    test "find_by_phone/2 finds entity by phone number" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:identifier, entity: entity, type: "phone", value: "+12025551234")

      assert %Entity{} = Entities.find_by_phone(user.id, "+12025551234")
      assert is_nil(Entities.find_by_phone(user.id, "+12025559999"))
    end

    test "find_by_exact_name/2 finds entity by exact name (case-insensitive)" do
      user = insert(:user)
      insert(:entity, owner: user, name: "John Doe")

      # Should find with exact case
      assert %Entity{} = Entities.find_by_exact_name(user.id, "John Doe")

      # Should find with different case
      assert %Entity{} = Entities.find_by_exact_name(user.id, "john doe")
      assert %Entity{} = Entities.find_by_exact_name(user.id, "JOHN DOE")

      # Should handle extra whitespace
      assert %Entity{} = Entities.find_by_exact_name(user.id, "  John Doe  ")

      # Should not find partial matches
      assert is_nil(Entities.find_by_exact_name(user.id, "John"))
      assert is_nil(Entities.find_by_exact_name(user.id, "Jane Doe"))
    end

    test "find_by_external_id/2 finds entity by metadata external_id" do
      user = insert(:user)
      _entity = insert(:entity, owner: user, metadata: %{"external_id" => "google_123"})

      assert %Entity{} = Entities.find_by_external_id(user.id, "google_123")
      assert is_nil(Entities.find_by_external_id(user.id, "google_456"))
    end

    test "find_by_any_external_id/2 finds entity by any external_id in external_ids map" do
      user = insert(:user)
      _entity = insert(:entity, owner: user, metadata: %{
        "external_ids" => %{
          "google_contacts" => "people/c123",
          "gmail" => "gmail:john@example.com",
          "google_calendar" => "gcal:john@example.com"
        },
        "sources" => ["google_contacts", "gmail", "google_calendar"]
      })

      # Should find by any of the external_ids
      assert %Entity{} = Entities.find_by_any_external_id(user.id, "people/c123")
      assert %Entity{} = Entities.find_by_any_external_id(user.id, "gmail:john@example.com")
      assert %Entity{} = Entities.find_by_any_external_id(user.id, "gcal:john@example.com")

      # Should not find non-existent external_id
      assert is_nil(Entities.find_by_any_external_id(user.id, "people/c999"))
    end
  end

  describe "duplicate detection and merging" do
    test "find_all_duplicates/1 finds entities with matching emails" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user, name: "John Doe")
      entity2 = insert(:entity, owner: user, name: "John D.")
      insert(:identifier, entity: entity1, type: "email", value: "john@example.com")
      insert(:identifier, entity: entity2, type: "email", value: "john@example.com")

      groups = Entities.find_all_duplicates(user.id)

      assert length(groups) == 1
      group = hd(groups)
      # Primary is the oldest (first inserted)
      assert group.primary.id == entity1.id
      assert length(group.duplicates) == 1
      assert hd(group.duplicates).id == entity2.id
    end

    test "find_all_duplicates/1 finds entities with matching phones" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user, name: "Jane Smith")
      entity2 = insert(:entity, owner: user, name: "Jane S.")
      insert(:identifier, entity: entity1, type: "phone", value: "+12025551234")
      insert(:identifier, entity: entity2, type: "phone", value: "+12025551234")

      groups = Entities.find_all_duplicates(user.id)

      assert length(groups) == 1
    end

    test "find_all_duplicates/1 finds entities with similar names" do
      user = insert(:user)
      _entity1 = insert(:entity, owner: user, name: "Robert Johnson")
      _entity2 = insert(:entity, owner: user, name: "Robert Johnson Jr")

      groups = Entities.find_all_duplicates(user.id)

      # Similar names should be grouped
      assert length(groups) == 1
    end

    test "find_all_duplicates/1 does not group unrelated entities" do
      user = insert(:user)
      _entity1 = insert(:entity, owner: user, name: "Alice")
      _entity2 = insert(:entity, owner: user, name: "Bob")

      groups = Entities.find_all_duplicates(user.id)

      assert Enum.empty?(groups)
    end

    test "merge_duplicate_entities/3 merges entities and moves identifiers" do
      user = insert(:user)
      primary = insert(:entity, owner: user, name: "Primary Person")
      duplicate = insert(:entity, owner: user, name: "Duplicate Person")
      insert(:identifier, entity: primary, type: "email", value: "primary@example.com")
      insert(:identifier, entity: duplicate, type: "email", value: "dup@example.com")
      insert(:identifier, entity: duplicate, type: "phone", value: "+12025559999")

      {:ok, merged} = Entities.merge_duplicate_entities(primary.id, [duplicate.id], user.id)

      assert merged.id == primary.id

      # Duplicate should be deleted
      assert is_nil(Entities.get_entity(duplicate.id))

      # Identifiers should be moved
      assert Entities.has_identifier?(primary.id, "email", "primary@example.com")
      assert Entities.has_identifier?(primary.id, "email", "dup@example.com")
      assert Entities.has_identifier?(primary.id, "phone", "+12025559999")
    end

    test "auto_merge_duplicates/1 merges all duplicate groups" do
      user = insert(:user)

      # Create first duplicate group (email match)
      entity1 = insert(:entity, owner: user, name: "Person One")
      entity2 = insert(:entity, owner: user, name: "Person 1")
      insert(:identifier, entity: entity1, type: "email", value: "person1@example.com")
      insert(:identifier, entity: entity2, type: "email", value: "person1@example.com")

      # Create second duplicate group (phone match)
      entity3 = insert(:entity, owner: user, name: "Another Person")
      entity4 = insert(:entity, owner: user, name: "Another P.")
      insert(:identifier, entity: entity3, type: "phone", value: "+12025551111")
      insert(:identifier, entity: entity4, type: "phone", value: "+12025551111")

      {:ok, stats} = Entities.auto_merge_duplicates(user.id)

      assert stats.merged_groups == 2
      assert stats.total_duplicates_removed == 2

      # Should only have 2 entities left
      {entities, _} = Entities.list_entities(user.id)
      assert length(entities) == 2
    end
  end

  describe "merge_entities/4" do
    test "merges source entity into target, transferring identifiers" do
      user = insert(:user)
      source = insert(:entity, owner: user, name: "Source Person")
      target = insert(:entity, owner: user, name: "Target Person")
      # Use is_primary: false to avoid unique constraint issues on primary identifiers
      insert(:identifier, entity: source, type: "email", value: "source@example.com", is_primary: false)
      insert(:identifier, entity: source, type: "phone", value: "+12025551111", is_primary: false)
      insert(:identifier, entity: target, type: "email", value: "target@example.com", is_primary: true)

      {:ok, {merged, summary}} = Entities.merge_entities(source.id, target.id, user.id, merge_tags: false)

      # Target entity is returned
      assert merged.id == target.id

      # Source entity is deleted
      assert is_nil(Entities.get_entity(source.id))

      # Identifiers are transferred
      assert summary.identifiers_added == 2
      assert Entities.has_identifier?(target.id, "email", "source@example.com")
      assert Entities.has_identifier?(target.id, "phone", "+12025551111")
      assert Entities.has_identifier?(target.id, "email", "target@example.com")
    end

    test "returns error when source entity not found" do
      user = insert(:user)
      target = insert(:entity, owner: user)

      result = Entities.merge_entities(Ecto.UUID.generate(), target.id, user.id)

      assert result == {:error, {:not_found, :source}}
    end

    test "returns error when target entity not found" do
      user = insert(:user)
      source = insert(:entity, owner: user)

      result = Entities.merge_entities(source.id, Ecto.UUID.generate(), user.id)

      assert result == {:error, {:not_found, :target}}
    end

    test "returns error when trying to merge entity with itself" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      result = Entities.merge_entities(entity.id, entity.id, user.id)

      assert result == {:error, :same_entity}
    end

    test "returns error when entity types don't match" do
      user = insert(:user)
      person = insert(:entity, owner: user, type: "person")
      org = insert(:entity, owner: user, type: "organization")

      result = Entities.merge_entities(person.id, org.id, user.id)

      assert result == {:error, :type_mismatch}
    end

    test "does not allow merging entities from different users" do
      user1 = insert(:user)
      user2 = insert(:user)
      source = insert(:entity, owner: user1)
      target = insert(:entity, owner: user2)

      # Try to merge as user1 - target belongs to user2
      result = Entities.merge_entities(source.id, target.id, user1.id)

      assert result == {:error, {:not_found, :target}}
    end

    test "transfers interactions from source to target" do
      user = insert(:user)
      source = insert(:entity, owner: user)
      target = insert(:entity, owner: user)

      # Create some interactions on the source
      insert(:interaction, user: user, entity: source, type: "call")
      insert(:interaction, user: user, entity: source, type: "email")

      {:ok, {_merged, summary}} = Entities.merge_entities(source.id, target.id, user.id, merge_tags: false)

      assert summary.interactions_transferred == 2
    end

    test "can skip tag merging with merge_tags: false" do
      user = insert(:user)
      source = insert(:entity, owner: user)
      target = insert(:entity, owner: user)

      {:ok, {_merged, summary}} = Entities.merge_entities(source.id, target.id, user.id, merge_tags: false)

      assert summary.tags_added == 0
    end

    test "handles primary identifier conflicts when both entities have primary identifiers of same type" do
      user = insert(:user)
      source = insert(:entity, owner: user, name: "Source Person")
      target = insert(:entity, owner: user, name: "Target Person")

      # Both entities have a primary email - this would cause a unique constraint violation
      # if not handled properly
      insert(:identifier, entity: source, type: "email", value: "source@example.com", is_primary: true)
      insert(:identifier, entity: target, type: "email", value: "target@example.com", is_primary: true)

      {:ok, {merged, summary}} = Entities.merge_entities(source.id, target.id, user.id, merge_tags: false)

      # Merge should succeed
      assert merged.id == target.id
      assert summary.identifiers_added == 1

      # Both emails should exist on the target
      assert Entities.has_identifier?(target.id, "email", "source@example.com")
      assert Entities.has_identifier?(target.id, "email", "target@example.com")

      # Target's original email should still be primary, source's should be non-primary
      identifiers = Entities.list_identifiers_for_entity(target.id)
      target_email = Enum.find(identifiers, &(&1.value == "target@example.com"))
      source_email = Enum.find(identifiers, &(&1.value == "source@example.com"))

      assert target_email.is_primary == true
      assert source_email.is_primary == false
    end

    test "skips duplicate identifiers when merging" do
      user = insert(:user)
      source = insert(:entity, owner: user, name: "Source Person")
      target = insert(:entity, owner: user, name: "Target Person")

      # Both entities have the same email
      insert(:identifier, entity: source, type: "email", value: "shared@example.com", is_primary: true)
      insert(:identifier, entity: target, type: "email", value: "shared@example.com", is_primary: true)

      {:ok, {merged, summary}} = Entities.merge_entities(source.id, target.id, user.id, merge_tags: false)

      # Merge should succeed
      assert merged.id == target.id

      # Duplicate identifier should be skipped (not added)
      assert summary.identifiers_added == 0

      # Target should still have only one email
      identifiers = Entities.list_identifiers_for_entity(target.id)
      email_identifiers = Enum.filter(identifiers, &(&1.type == "email"))
      assert length(email_identifiers) == 1
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

      # Use create_identifier which goes through changeset and generates value_hash
      {:ok, _identifier} = Entities.create_identifier(%{
        entity_id: entity.id,
        type: "email",
        value: "test@example.com"
      })

      duplicates = Entities.check_identifier_duplicates("email", "test@example.com")
      assert length(duplicates) == 1
    end

    test "archive_identifier/1 sets archived_at timestamp" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, identifier} = Entities.create_identifier(%{
        entity_id: entity.id,
        type: "email",
        value: "old@example.com"
      })

      assert {:ok, archived} = Entities.archive_identifier(identifier)
      assert archived.archived_at
    end

    test "unarchive_identifier/1 clears archived_at timestamp" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      {:ok, identifier} = Entities.create_identifier(%{
        entity_id: entity.id,
        type: "email",
        value: "old@example.com"
      })

      {:ok, archived} = Entities.archive_identifier(identifier)
      assert archived.archived_at

      {:ok, unarchived} = Entities.unarchive_identifier(archived)
      assert is_nil(unarchived.archived_at)
    end

    test "list_active_identifiers_for_entity/1 excludes archived identifiers" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      {:ok, active} = Entities.create_identifier(%{
        entity_id: entity.id,
        type: "email",
        value: "current@example.com"
      })

      {:ok, to_archive} = Entities.create_identifier(%{
        entity_id: entity.id,
        type: "email",
        value: "old@example.com"
      })

      {:ok, _archived} = Entities.archive_identifier(to_archive)

      active_identifiers = Entities.list_active_identifiers_for_entity(entity.id)
      assert length(active_identifiers) == 1
      assert hd(active_identifiers).id == active.id
    end

    test "list_archived_identifiers_for_entity/1 returns only archived identifiers" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      {:ok, _active} = Entities.create_identifier(%{
        entity_id: entity.id,
        type: "email",
        value: "current@example.com"
      })

      {:ok, to_archive} = Entities.create_identifier(%{
        entity_id: entity.id,
        type: "email",
        value: "old@example.com"
      })

      {:ok, archived} = Entities.archive_identifier(to_archive)

      archived_identifiers = Entities.list_archived_identifiers_for_entity(entity.id)
      assert length(archived_identifiers) == 1
      assert hd(archived_identifiers).id == archived.id
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

  describe "entity_relationships" do
    alias Conezia.Entities.EntityRelationship

    test "create_entity_relationship/1 creates relationship between two entities" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      attrs = %{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend",
        subtype: "friend"
      }

      assert {:ok, %EntityRelationship{} = rel} = Entities.create_entity_relationship(attrs)
      assert rel.source_entity_id == entity1.id
      assert rel.target_entity_id == entity2.id
      assert rel.type == "friend"
    end

    test "create_entity_relationship/1 with asymmetric relationship sets inverse" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      attrs = %{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "family",
        subtype: "parent"
      }

      assert {:ok, %EntityRelationship{} = rel} = Entities.create_entity_relationship(attrs)
      assert rel.subtype == "parent"
      assert rel.inverse_subtype == "child"
      assert rel.is_bidirectional == false
    end

    test "create_entity_relationship/1 with symmetric relationship stays bidirectional" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      attrs = %{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend",
        subtype: "friend"
      }

      assert {:ok, %EntityRelationship{} = rel} = Entities.create_entity_relationship(attrs)
      assert rel.is_bidirectional == true
    end

    test "create_entity_relationship/1 fails when source equals target" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      attrs = %{
        user_id: user.id,
        source_entity_id: entity.id,
        target_entity_id: entity.id,
        type: "friend"
      }

      assert {:error, changeset} = Entities.create_entity_relationship(attrs)
      assert {"cannot be the same as source entity", _} = changeset.errors[:target_entity_id]
    end

    test "create_entity_relationship/1 creates relationship without type or subtype" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      attrs = %{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id
      }

      assert {:ok, %EntityRelationship{} = rel} = Entities.create_entity_relationship(attrs)
      assert rel.source_entity_id == entity1.id
      assert rel.target_entity_id == entity2.id
      assert is_nil(rel.type)
      assert is_nil(rel.subtype)
    end

    test "create_entity_relationship/1 creates relationship with notes" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      attrs = %{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend",
        notes: "Met at a conference in 2020"
      }

      assert {:ok, %EntityRelationship{} = rel} = Entities.create_entity_relationship(attrs)
      assert rel.notes == "Met at a conference in 2020"
    end

    test "list_entity_relationships_for_entity/3 returns relationships for entity" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)
      entity3 = insert(:entity, owner: user)

      {:ok, _} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend"
      })
      {:ok, _} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity3.id,
        target_entity_id: entity1.id,
        type: "colleague"
      })

      relationships = Entities.list_entity_relationships_for_entity(entity1.id, user.id)
      assert length(relationships) == 2
    end

    test "list_entity_relationships_for_entity/3 preloads entities" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user, name: "Alice")
      entity2 = insert(:entity, owner: user, name: "Bob")

      {:ok, _} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend"
      })

      [rel] = Entities.list_entity_relationships_for_entity(entity1.id, user.id)
      assert rel.source_entity.name == "Alice"
      assert rel.target_entity.name == "Bob"
    end

    test "get_entity_relationship_between/3 finds relationship in either direction" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      {:ok, created} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend"
      })

      # Find from source perspective
      rel1 = Entities.get_entity_relationship_between(user.id, entity1.id, entity2.id)
      assert rel1.id == created.id

      # Find from target perspective (reverse order)
      rel2 = Entities.get_entity_relationship_between(user.id, entity2.id, entity1.id)
      assert rel2.id == created.id
    end

    test "delete_entity_relationship/1 deletes relationship" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      {:ok, rel} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend"
      })

      assert {:ok, _} = Entities.delete_entity_relationship(rel)
      assert is_nil(Entities.get_entity_relationship(rel.id))
    end

    test "update_entity_relationship/2 updates relationship" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      {:ok, rel} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend"
      })

      assert {:ok, updated} = Entities.update_entity_relationship(rel, %{custom_label: "Best Friends"})
      assert updated.custom_label == "Best Friends"
    end

    test "unique constraint prevents duplicate relationships" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)

      {:ok, _} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "friend"
      })

      # Trying to create the same relationship again should fail
      assert {:error, changeset} = Entities.create_entity_relationship(%{
        user_id: user.id,
        source_entity_id: entity1.id,
        target_entity_id: entity2.id,
        type: "colleague"
      })
      assert changeset.errors != []
    end
  end

  describe "EntityRelationship display helpers" do
    alias Conezia.Entities.EntityRelationship

    test "display_label_for_source/1 returns custom_label when present" do
      rel = %EntityRelationship{
        type: "friend",
        subtype: "friend",
        custom_label: "Best Friend"
      }
      assert EntityRelationship.display_label_for_source(rel) == "Best Friend"
    end

    test "display_label_for_source/1 returns subtype when no custom_label" do
      rel = %EntityRelationship{
        type: "family",
        subtype: "parent",
        custom_label: nil
      }
      assert EntityRelationship.display_label_for_source(rel) == "Parent"
    end

    test "display_label_for_source/1 returns type when no subtype" do
      rel = %EntityRelationship{
        type: "friend",
        subtype: nil,
        custom_label: nil
      }
      assert EntityRelationship.display_label_for_source(rel) == "Friend"
    end

    test "display_label_for_target/1 returns same as source for bidirectional" do
      rel = %EntityRelationship{
        type: "friend",
        subtype: "friend",
        is_bidirectional: true
      }
      assert EntityRelationship.display_label_for_target(rel) == "Friend"
    end

    test "display_label_for_target/1 returns inverse for directional" do
      rel = %EntityRelationship{
        type: "family",
        subtype: "parent",
        inverse_type: "family",
        inverse_subtype: "child",
        is_bidirectional: false
      }
      assert EntityRelationship.display_label_for_target(rel) == "Child"
    end

    test "display_label_for/2 returns correct label based on perspective" do
      source_id = Ecto.UUID.generate()
      target_id = Ecto.UUID.generate()

      rel = %EntityRelationship{
        source_entity_id: source_id,
        target_entity_id: target_id,
        type: "family",
        subtype: "parent",
        inverse_type: "family",
        inverse_subtype: "child",
        is_bidirectional: false
      }

      # From source perspective: "parent"
      assert EntityRelationship.display_label_for(rel, source_id) == "Parent"

      # From target perspective: "child"
      assert EntityRelationship.display_label_for(rel, target_id) == "Child"
    end

    test "other_entity_id/2 returns the other entity's ID" do
      source_id = Ecto.UUID.generate()
      target_id = Ecto.UUID.generate()

      rel = %EntityRelationship{
        source_entity_id: source_id,
        target_entity_id: target_id
      }

      assert EntityRelationship.other_entity_id(rel, source_id) == target_id
      assert EntityRelationship.other_entity_id(rel, target_id) == source_id
    end

    test "symmetric_types/0 returns symmetric types" do
      types = EntityRelationship.symmetric_types()
      assert "friend" in types
      assert "colleague" in types
      assert "neighbor" in types
    end

    test "asymmetric_pairs/0 returns pairs" do
      pairs = EntityRelationship.asymmetric_pairs()
      assert pairs["parent"] == "child"
      assert pairs["mentor"] == "mentee"
      assert pairs["employer"] == "employee"
    end

    test "inverse_of/1 returns inverse subtype" do
      assert EntityRelationship.inverse_of("parent") == "child"
      assert EntityRelationship.inverse_of("mentee") == "mentor"
      assert is_nil(EntityRelationship.inverse_of("friend"))
    end
  end
end
