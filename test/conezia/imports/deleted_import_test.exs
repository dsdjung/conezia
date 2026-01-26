defmodule Conezia.Imports.DeletedImportTest do
  use Conezia.DataCase, async: true

  alias Conezia.Imports
  alias Conezia.Entities

  import Conezia.Factory

  describe "record_deleted_import/3" do
    test "records a single deleted import" do
      user = insert(:user)

      assert {:ok, _} = Imports.record_deleted_import(
        user.id,
        "google:123",
        "google_contacts",
        entity_name: "John Doe",
        entity_email: "john@example.com"
      )

      assert Imports.is_deleted_import?(user.id, "google:123", "google_contacts")
    end

    test "handles duplicate inserts gracefully" do
      user = insert(:user)

      {:ok, _} = Imports.record_deleted_import(user.id, "google:123", "google_contacts", [])
      {:ok, _} = Imports.record_deleted_import(user.id, "google:123", "google_contacts", [])

      # Should still work without error
      assert Imports.is_deleted_import?(user.id, "google:123", "google_contacts")
    end
  end

  describe "record_deleted_import/2 with map" do
    test "records multiple external IDs at once" do
      user = insert(:user)

      external_ids = %{
        "google_contacts" => "people/123",
        "gmail" => "gmail:test@example.com"
      }

      assert :ok = Imports.record_deleted_import(user.id, external_ids, entity_name: "Test User")

      assert Imports.is_deleted_import?(user.id, "people/123", "google_contacts")
      assert Imports.is_deleted_import?(user.id, "gmail:test@example.com", "gmail")
    end
  end

  describe "is_deleted_import?/3" do
    test "returns false for non-deleted imports" do
      user = insert(:user)
      refute Imports.is_deleted_import?(user.id, "unknown:123", "unknown")
    end

    test "returns true for deleted imports" do
      user = insert(:user)
      {:ok, _} = Imports.record_deleted_import(user.id, "ext:123", "google", [])

      assert Imports.is_deleted_import?(user.id, "ext:123", "google")
    end

    test "is scoped to user" do
      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, _} = Imports.record_deleted_import(user1.id, "ext:123", "google", [])

      assert Imports.is_deleted_import?(user1.id, "ext:123", "google")
      refute Imports.is_deleted_import?(user2.id, "ext:123", "google")
    end
  end

  describe "any_deleted_import?/2" do
    test "returns true if any external ID is deleted" do
      user = insert(:user)
      {:ok, _} = Imports.record_deleted_import(user.id, "gmail:test@example.com", "gmail", [])

      external_ids = %{
        "google_contacts" => "people/123",
        "gmail" => "gmail:test@example.com"
      }

      assert Imports.any_deleted_import?(user.id, external_ids)
    end

    test "returns false if no external IDs are deleted" do
      user = insert(:user)

      external_ids = %{
        "google_contacts" => "people/123",
        "gmail" => "gmail:test@example.com"
      }

      refute Imports.any_deleted_import?(user.id, external_ids)
    end
  end

  describe "get_deleted_external_ids/2" do
    test "returns a MapSet of deleted external IDs for a source" do
      user = insert(:user)

      {:ok, _} = Imports.record_deleted_import(user.id, "ext:1", "google", [])
      {:ok, _} = Imports.record_deleted_import(user.id, "ext:2", "google", [])
      {:ok, _} = Imports.record_deleted_import(user.id, "ext:3", "gmail", [])

      google_ids = Imports.get_deleted_external_ids(user.id, "google")

      assert MapSet.member?(google_ids, "ext:1")
      assert MapSet.member?(google_ids, "ext:2")
      refute MapSet.member?(google_ids, "ext:3")
    end
  end

  describe "undelete_import/3" do
    test "removes the deleted import record" do
      user = insert(:user)

      {:ok, _} = Imports.record_deleted_import(user.id, "ext:123", "google", [])
      assert Imports.is_deleted_import?(user.id, "ext:123", "google")

      :ok = Imports.undelete_import(user.id, "ext:123", "google")

      refute Imports.is_deleted_import?(user.id, "ext:123", "google")
    end
  end

  describe "entity deletion records external IDs" do
    test "deleting an entity records its external IDs" do
      user = insert(:user)

      entity = insert(:entity,
        owner: user,
        name: "Test Person",
        metadata: %{
          "external_ids" => %{
            "google_contacts" => "people/123",
            "gmail" => "gmail:test@example.com"
          },
          "source" => "google_contacts"
        }
      )

      # Add an email identifier
      insert(:identifier, entity: entity, type: "email", value: "test@example.com")

      # Delete the entity
      {:ok, _} = Entities.delete_entity(entity)

      # The external IDs should be recorded as deleted
      assert Imports.is_deleted_import?(user.id, "people/123", "google_contacts")
      assert Imports.is_deleted_import?(user.id, "gmail:test@example.com", "gmail")
    end

    test "deleting an entity with legacy external_id format records it" do
      user = insert(:user)

      entity = insert(:entity,
        owner: user,
        name: "Legacy Entity",
        metadata: %{
          "external_id" => "legacy:123",
          "source" => "google_contacts"
        }
      )

      {:ok, _} = Entities.delete_entity(entity)

      assert Imports.is_deleted_import?(user.id, "legacy:123", "google_contacts")
    end

    test "deleting an entity without external IDs works fine" do
      user = insert(:user)
      entity = insert(:entity, owner: user, metadata: %{})

      {:ok, _} = Entities.delete_entity(entity)

      # Should not have recorded anything, but should not error
      deleted_imports = Imports.list_deleted_imports(user.id)
      assert deleted_imports == []
    end
  end
end
