defmodule Conezia.Vault do
  @moduledoc """
  Field-level encryption vault for sensitive data.

  Provides AES-256-GCM encryption for sensitive fields like SSN, account numbers,
  API tokens, etc. The encryption key is derived from application configuration.

  ## Configuration

      config :conezia, Conezia.Vault,
        secret_key: "32-byte-secret-key-for-aes-256!"

  ## Usage

  In schemas, use the vault for encrypting/decrypting fields:

      defmodule MySchema do
        import Ecto.Changeset

        def changeset(struct, attrs) do
          struct
          |> cast(attrs, [:ssn])
          |> Conezia.Vault.encrypt_field(:ssn)
        end
      end

  ## Security Notes

  - Uses AES-256-GCM which provides both confidentiality and authenticity
  - Each encryption generates a unique IV (nonce) for semantic security
  - The IV is prepended to the ciphertext for storage
  - Key rotation support is planned but not yet implemented
  """

  @aad "conezia_vault_v1"

  @doc """
  Encrypt a value using AES-256-GCM.

  Returns the encrypted value as a base64-encoded string containing:
  - 12-byte IV
  - ciphertext
  - 16-byte authentication tag
  """
  @spec encrypt(String.t() | nil) :: String.t() | nil
  def encrypt(nil), do: nil
  def encrypt(""), do: ""
  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} = :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      key,
      iv,
      plaintext,
      @aad,
      true
    )

    (iv <> tag <> ciphertext)
    |> Base.encode64()
  end

  @doc """
  Decrypt a value that was encrypted with `encrypt/1`.

  Returns `{:ok, plaintext}` on success or `{:error, reason}` on failure.
  """
  @spec decrypt(String.t() | nil) :: {:ok, String.t() | nil} | {:error, term()}
  def decrypt(nil), do: {:ok, nil}
  def decrypt(""), do: {:ok, ""}
  def decrypt(encrypted) when is_binary(encrypted) do
    with {:ok, data} <- Base.decode64(encrypted),
         <<iv::binary-12, tag::binary-16, ciphertext::binary>> <- data do
      key = get_key()

      case :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key,
        iv,
        ciphertext,
        @aad,
        tag,
        false
      ) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> {:error, :decryption_failed}
      end
    else
      :error -> {:error, :invalid_base64}
      _ -> {:error, :invalid_format}
    end
  end

  @doc """
  Decrypt a value, returning the plaintext or nil on error.
  """
  @spec decrypt!(String.t() | nil) :: String.t() | nil
  def decrypt!(value) do
    case decrypt(value) do
      {:ok, plaintext} -> plaintext
      {:error, _} -> nil
    end
  end

  @doc """
  Encrypt a changeset field.

  Use in changeset pipelines to encrypt sensitive fields before storage.
  """
  def encrypt_field(changeset, field) do
    case Ecto.Changeset.get_change(changeset, field) do
      nil -> changeset
      value -> Ecto.Changeset.put_change(changeset, field, encrypt(value))
    end
  end

  @doc """
  Hash a value for lookups.

  When you need to search by an encrypted field, store a hash alongside
  the encrypted value. This hash can be indexed and searched.

  Note: This is a one-way operation and cannot be reversed.
  """
  @spec hash(String.t() | nil) :: String.t() | nil
  def hash(nil), do: nil
  def hash(""), do: ""
  def hash(value) when is_binary(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generate a blind index for searching encrypted fields.

  Uses HMAC-SHA256 with a derived key for deterministic but secure hashing.
  """
  @spec blind_index(String.t() | nil, String.t()) :: String.t() | nil
  def blind_index(nil, _field), do: nil
  def blind_index("", _field), do: ""
  def blind_index(value, field) when is_binary(value) and is_binary(field) do
    key = derive_key(field)
    :crypto.mac(:hmac, :sha256, key, value)
    |> Base.encode16(case: :lower)
  end

  defp derive_key(purpose) do
    master_key = get_key()
    :crypto.mac(:hmac, :sha256, master_key, "blind_index:#{purpose}")
  end

  defp get_key do
    key = Application.get_env(:conezia, __MODULE__, [])[:secret_key]
      || raise "Conezia.Vault secret_key not configured"

    # Ensure key is exactly 32 bytes
    case byte_size(key) do
      32 -> key
      size when size < 32 ->
        # Pad with derived bytes (not recommended for production)
        :crypto.hash(:sha256, key)
      _ ->
        # Truncate (not recommended for production)
        binary_part(key, 0, 32)
    end
  end

  @doc """
  Check if the vault is properly configured.
  """
  def configured? do
    case Application.get_env(:conezia, __MODULE__, [])[:secret_key] do
      nil -> false
      "" -> false
      _ -> true
    end
  end
end
