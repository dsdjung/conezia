defmodule Conezia.Repo.Migrations.EncryptSensitiveTokens do
  @moduledoc """
  Migration to encrypt existing plaintext tokens in auth_providers and webhooks tables.

  This migration encrypts any existing plaintext data that was stored before
  the Conezia.Encrypted.Binary type was applied to these columns.

  Note: The column types (binary) remain the same, only the data format changes
  from plaintext to encrypted (base64-encoded AES-256-GCM ciphertext).
  """
  use Ecto.Migration

  alias Conezia.Vault

  def up do
    # Encrypt auth_providers tokens
    execute(fn ->
      repo().query!(
        "SELECT id, provider_token, provider_refresh_token FROM auth_providers WHERE provider_token IS NOT NULL OR provider_refresh_token IS NOT NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, token, refresh_token] ->
        encrypted_token = maybe_encrypt(token)
        encrypted_refresh = maybe_encrypt(refresh_token)

        repo().query!(
          "UPDATE auth_providers SET provider_token = $1, provider_refresh_token = $2 WHERE id = $3",
          [encrypted_token, encrypted_refresh, id]
        )
      end)
    end)

    # Encrypt webhook secrets
    execute(fn ->
      repo().query!(
        "SELECT id, secret FROM webhooks WHERE secret IS NOT NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, secret] ->
        encrypted_secret = maybe_encrypt(secret)

        repo().query!(
          "UPDATE webhooks SET secret = $1 WHERE id = $2",
          [encrypted_secret, id]
        )
      end)
    end)
  end

  def down do
    # Decrypt auth_providers tokens (reversible)
    execute(fn ->
      repo().query!(
        "SELECT id, provider_token, provider_refresh_token FROM auth_providers WHERE provider_token IS NOT NULL OR provider_refresh_token IS NOT NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, token, refresh_token] ->
        decrypted_token = maybe_decrypt(token)
        decrypted_refresh = maybe_decrypt(refresh_token)

        repo().query!(
          "UPDATE auth_providers SET provider_token = $1, provider_refresh_token = $2 WHERE id = $3",
          [decrypted_token, decrypted_refresh, id]
        )
      end)
    end)

    # Decrypt webhook secrets (reversible)
    execute(fn ->
      repo().query!(
        "SELECT id, secret FROM webhooks WHERE secret IS NOT NULL"
      )
      |> Map.get(:rows, [])
      |> Enum.each(fn [id, secret] ->
        decrypted_secret = maybe_decrypt(secret)

        repo().query!(
          "UPDATE webhooks SET secret = $1 WHERE id = $2",
          [decrypted_secret, id]
        )
      end)
    end)
  end

  # Only encrypt if not already encrypted (check for base64 pattern)
  defp maybe_encrypt(nil), do: nil
  defp maybe_encrypt(value) when is_binary(value) do
    if already_encrypted?(value) do
      value
    else
      Vault.encrypt(value)
    end
  end

  defp maybe_decrypt(nil), do: nil
  defp maybe_decrypt(value) when is_binary(value) do
    case Vault.decrypt(value) do
      {:ok, decrypted} -> decrypted
      {:error, _} -> value  # Already plaintext
    end
  end

  # Check if value looks like our encrypted format (base64 with correct length)
  defp already_encrypted?(value) do
    case Base.decode64(value) do
      {:ok, decoded} when byte_size(decoded) >= 29 ->
        # 12 bytes IV + 16 bytes tag + at least 1 byte ciphertext = 29+ bytes
        true
      _ ->
        false
    end
  end
end
