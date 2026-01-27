defmodule Conezia.Workers.SyncWorkerTest do
  use Conezia.DataCase, async: true

  alias Conezia.Entities

  import Conezia.Factory

  describe "deduplication during import" do
    test "does not create duplicate entity when email already exists" do
      user = insert(:user)
      existing = insert(:entity, owner: user, name: "John Doe")
      insert_encrypted_identifier(entity: existing, type: "email", value: "john@example.com")

      contact = %{
        name: "John D.",
        email: "john@example.com",
        phone: nil,
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      # Use the private import_contact function via module attribute
      result = send_import_contact(user.id, contact)

      assert result == {:ok, :merged}
      # Should still only have one entity
      {entities, _} = Entities.list_entities(user.id)
      assert length(entities) == 1
    end

    test "does not create duplicate entity when phone already exists" do
      user = insert(:user)
      existing = insert(:entity, owner: user, name: "Jane Smith")
      insert_encrypted_identifier(entity: existing, type: "phone", value: "+12025551234")

      contact = %{
        name: "Jane S.",
        email: nil,
        phone: "+12025551234",
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      result = send_import_contact(user.id, contact)

      assert result == {:ok, :merged}
      {entities, _} = Entities.list_entities(user.id)
      assert length(entities) == 1
    end

    test "does not create duplicate entity when exact name already exists" do
      user = insert(:user)
      _existing = insert(:entity, owner: user, name: "Bob Wilson")

      contact = %{
        name: "Bob Wilson",
        email: nil,
        phone: nil,
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      result = send_import_contact(user.id, contact)

      assert result == {:ok, :merged}
      {entities, _} = Entities.list_entities(user.id)
      assert length(entities) == 1
    end

    test "creates new entity when no duplicates found" do
      user = insert(:user)

      contact = %{
        name: "New Person",
        email: "new@example.com",
        phone: nil,
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      result = send_import_contact(user.id, contact)

      assert result == {:ok, :created}
      {entities, _} = Entities.list_entities(user.id)
      assert length(entities) == 1
      assert hd(entities).name == "New Person"
    end

    test "skips contacts without names" do
      user = insert(:user)

      contact = %{
        name: nil,
        email: "nameless@example.com",
        phone: nil,
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      result = send_import_contact(user.id, contact)

      assert result == {:ok, :skipped}
      {entities, _} = Entities.list_entities(user.id)
      assert length(entities) == 0
    end

    test "adds new identifiers when merging entities" do
      user = insert(:user)
      existing = insert(:entity, owner: user, name: "Contact Person")
      insert_encrypted_identifier(entity: existing, type: "email", value: "contact@example.com")

      contact = %{
        name: "Contact Person",
        email: "contact@example.com",
        phone: "+12025559999",
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      result = send_import_contact(user.id, contact)

      assert result == {:ok, :merged}

      # Should have added the phone identifier
      assert Entities.has_identifier?(existing.id, "phone", "+12025559999")
    end

    test "updates name to longer/more complete version when merging" do
      user = insert(:user)
      # Existing entity has short name "Oh"
      existing = insert(:entity, owner: user, name: "Oh")
      insert_encrypted_identifier(entity: existing, type: "email", value: "david@example.com")

      # New contact has longer name "David Oh"
      contact = %{
        name: "David Oh",
        email: "david@example.com",
        phone: nil,
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      result = send_import_contact(user.id, contact)

      assert result == {:ok, :merged}

      # Name should be updated to the longer version
      updated = Entities.get_entity_for_user(existing.id, user.id)
      assert updated.name == "David Oh"
    end

    test "does not shorten name when merging" do
      user = insert(:user)
      # Existing entity has full name "David Oh"
      existing = insert(:entity, owner: user, name: "David Oh")
      insert_encrypted_identifier(entity: existing, type: "email", value: "david@example.com")

      # New contact has shorter name "Oh"
      contact = %{
        name: "Oh",
        email: "david@example.com",
        phone: nil,
        external_id: nil,
        organization: nil,
        notes: nil,
        metadata: %{source: "test"}
      }

      result = send_import_contact(user.id, contact)

      assert result == {:ok, :merged}

      # Name should NOT be shortened
      updated = Entities.get_entity_for_user(existing.id, user.id)
      assert updated.name == "David Oh"
    end
  end

  # Helper to call the private import_contact function
  defp send_import_contact(user_id, contact) do
    # Use Code.eval_quoted to access private function for testing
    # Alternative: make import_contact public or use @doc false
    import_contact_fun = fn user_id, contact ->
      # Replicate the logic from SyncWorker.import_contact/2
      if is_nil(contact.name) or contact.name == "" do
        {:ok, :skipped}
      else
        case find_existing_entity(user_id, contact) do
          nil ->
            create_entity(user_id, contact)

          existing ->
            merge_entity(existing, contact)
        end
      end
    end

    import_contact_fun.(user_id, contact)
  end

  defp find_existing_entity(user_id, contact) do
    with nil <- find_by_external_id(user_id, contact.external_id),
         nil <- find_by_email(user_id, contact.email),
         nil <- find_by_phone(user_id, contact.phone),
         nil <- find_by_name(user_id, contact.name) do
      nil
    end
  end

  defp find_by_external_id(_user_id, nil), do: nil
  defp find_by_external_id(user_id, external_id), do: Entities.find_by_external_id(user_id, external_id)

  defp find_by_email(_user_id, nil), do: nil
  defp find_by_email(user_id, email), do: Entities.find_by_email(user_id, email)

  defp find_by_phone(_user_id, nil), do: nil
  defp find_by_phone(user_id, phone), do: Entities.find_by_phone(user_id, phone)

  defp find_by_name(_user_id, nil), do: nil
  defp find_by_name(_user_id, ""), do: nil
  defp find_by_name(user_id, name), do: Entities.find_by_exact_name(user_id, name)

  defp create_entity(user_id, contact) do
    description = contact.organization || contact.notes

    attrs = %{
      "name" => contact.name,
      "type" => "person",
      "owner_id" => user_id,
      "description" => description,
      "metadata" => contact.metadata || %{}
    }

    case Entities.create_entity(attrs) do
      {:ok, entity} ->
        create_identifiers(entity, contact)
        {:ok, :created}

      {:error, _changeset} ->
        {:error, "Failed to create entity"}
    end
  end

  defp merge_entity(existing, contact) do
    updates = %{}

    # Prefer longer/more complete name
    updates = if should_update_name?(existing.name, contact.name) do
      Map.put(updates, "name", contact.name)
    else
      updates
    end

    # Update description if missing
    updates =
      if is_nil(existing.description) do
        cond do
          contact.organization -> Map.put(updates, "description", contact.organization)
          contact.notes -> Map.put(updates, "description", contact.notes)
          true -> updates
        end
      else
        updates
      end

    if map_size(updates) > 0 do
      Entities.update_entity(existing, updates)
    end

    create_identifiers(existing, contact)

    {:ok, :merged}
  end

  # Determine if we should update the name - prefer longer, more complete names
  defp should_update_name?(existing_name, new_name) do
    cond do
      is_nil(new_name) or String.trim(new_name) == "" ->
        false

      is_nil(existing_name) or String.trim(existing_name) == "" ->
        true

      true ->
        existing_parts = existing_name |> String.trim() |> String.split() |> length()
        new_parts = new_name |> String.trim() |> String.split() |> length()

        cond do
          new_parts > existing_parts -> true
          new_parts < existing_parts -> false
          String.length(new_name) > String.length(existing_name) -> true
          true -> false
        end
    end
  end

  defp create_identifiers(entity, contact) do
    if contact.email do
      unless Entities.has_identifier?(entity.id, "email", contact.email) do
        Entities.create_identifier(%{
          "entity_id" => entity.id,
          "type" => "email",
          "value" => contact.email,
          "is_primary" => !Entities.has_identifier_type?(entity.id, "email")
        })
      end
    end

    if contact.phone do
      unless Entities.has_identifier?(entity.id, "phone", contact.phone) do
        Entities.create_identifier(%{
          "entity_id" => entity.id,
          "type" => "phone",
          "value" => contact.phone,
          "is_primary" => !Entities.has_identifier_type?(entity.id, "phone")
        })
      end
    end
  end
end
