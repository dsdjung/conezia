defmodule Conezia.Repo.Migrations.EncryptExistingData do
  use Ecto.Migration

  alias Conezia.Vault

  @moduledoc """
  Encrypt existing plaintext data across all tables.
  This migration:
  1. Encrypts all non-sensitive identifier values (phone, email, etc.)
  2. Encrypts entity descriptions
  3. Encrypts custom field values
  4. Encrypts interaction titles/content
  5. Encrypts communication subjects/content
  6. Encrypts gift names/descriptions/notes
  7. Encrypts reminder titles/descriptions
  """

  def up do
    # 1. Encrypt identifier values that are still in plaintext
    # (SSN/government_id/account_number are already encrypted)
    execute(fn ->
      repo().query!(
        "SELECT id, type, value FROM identifiers WHERE value IS NOT NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, type, value] ->
        encrypted = Vault.encrypt(value)
        hash = Vault.blind_index(value, "identifier_#{type}")

        repo().query!(
          "UPDATE identifiers SET value_encrypted = $1, value_hash = COALESCE(value_hash, $2), value = NULL WHERE id = $3",
          [encrypted, hash, id]
        )
      end)
    end)

    # 2. Encrypt entity descriptions
    execute(fn ->
      repo().query!(
        "SELECT id, description FROM entities WHERE description IS NOT NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, description] ->
        encrypted = Vault.encrypt(description)

        repo().query!(
          "UPDATE entities SET description_encrypted = $1 WHERE id = $2",
          [encrypted, id]
        )
      end)
    end)

    # 3. Encrypt custom field values
    execute(fn ->
      repo().query!(
        "SELECT id, value, number_value FROM custom_fields WHERE value IS NOT NULL OR number_value IS NOT NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, value, number_value] ->
        value_enc = if value, do: Vault.encrypt(value), else: nil
        number_enc = if number_value, do: Vault.encrypt(Decimal.to_string(number_value)), else: nil

        repo().query!(
          "UPDATE custom_fields SET value_encrypted = $1, number_value_encrypted = $2 WHERE id = $3",
          [value_enc, number_enc, id]
        )
      end)
    end)

    # 4. Encrypt interaction titles and content
    execute(fn ->
      repo().query!(
        "SELECT id, title, content FROM interactions"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, title, content] ->
        title_enc = if title, do: Vault.encrypt(title), else: nil
        content_enc = if content, do: Vault.encrypt(content), else: nil

        repo().query!(
          "UPDATE interactions SET title_encrypted = $1, content_encrypted = $2 WHERE id = $3",
          [title_enc, content_enc, id]
        )
      end)
    end)

    # 5. Encrypt communication subjects and content
    execute(fn ->
      repo().query!(
        "SELECT id, subject, content FROM communications"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, subject, content] ->
        subject_enc = if subject, do: Vault.encrypt(subject), else: nil
        content_enc = if content, do: Vault.encrypt(content), else: nil

        repo().query!(
          "UPDATE communications SET subject_encrypted = $1, content_encrypted = $2 WHERE id = $3",
          [subject_enc, content_enc, id]
        )
      end)
    end)

    # 6. Encrypt gift names, descriptions, notes
    execute(fn ->
      repo().query!(
        "SELECT id, name, description, notes FROM gifts"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, name, description, notes] ->
        name_enc = if name, do: Vault.encrypt(name), else: nil
        desc_enc = if description, do: Vault.encrypt(description), else: nil
        notes_enc = if notes, do: Vault.encrypt(notes), else: nil

        repo().query!(
          "UPDATE gifts SET name_encrypted = $1, description_encrypted = $2, notes_encrypted = $3 WHERE id = $4",
          [name_enc, desc_enc, notes_enc, id]
        )
      end)
    end)

    # 7. Encrypt reminder titles and descriptions
    execute(fn ->
      repo().query!(
        "SELECT id, title, description FROM reminders"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, title, description] ->
        title_enc = if title, do: Vault.encrypt(title), else: nil
        desc_enc = if description, do: Vault.encrypt(description), else: nil

        repo().query!(
          "UPDATE reminders SET title_encrypted = $1, description_encrypted = $2 WHERE id = $3",
          [title_enc, desc_enc, id]
        )
      end)
    end)
  end

  def down do
    # Reverse: decrypt identifier values back to plaintext
    execute(fn ->
      repo().query!(
        "SELECT id, value_encrypted FROM identifiers WHERE value_encrypted IS NOT NULL AND value IS NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, encrypted] ->
        case Vault.decrypt(encrypted) do
          {:ok, plaintext} ->
            repo().query!(
              "UPDATE identifiers SET value = $1 WHERE id = $2",
              [plaintext, id]
            )
          {:error, _} -> :ok
        end
      end)
    end)

    # Clear encrypted columns (data preserved in plaintext columns)
    execute("UPDATE entities SET description_encrypted = NULL")
    execute("UPDATE custom_fields SET value_encrypted = NULL, number_value_encrypted = NULL")
    execute("UPDATE interactions SET title_encrypted = NULL, content_encrypted = NULL")
    execute("UPDATE communications SET subject_encrypted = NULL, content_encrypted = NULL")
    execute("UPDATE gifts SET name_encrypted = NULL, description_encrypted = NULL, notes_encrypted = NULL")
    execute("UPDATE reminders SET title_encrypted = NULL, description_encrypted = NULL")
  end
end
