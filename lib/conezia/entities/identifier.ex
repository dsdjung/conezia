defmodule Conezia.Entities.Identifier do
  @moduledoc """
  Identifier schema for entity contact information (email, phone, social handles, etc).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @identifier_types ~w(phone email ssn government_id account_number social_handle website)
  @sensitive_types ~w(ssn government_id account_number)

  schema "identifiers" do
    field :type, :string
    field :value, :string
    field :value_encrypted, :binary
    field :value_hash, :string
    field :label, :string
    field :is_primary, :boolean, default: false
    field :verified_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec

    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :entity_id]
  @optional_fields [:value, :label, :is_primary, :verified_at, :archived_at]

  def changeset(identifier, attrs) do
    identifier
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @identifier_types)
    |> validate_length(:label, max: 64)
    |> validate_identifier_value()
    |> hash_value_for_duplicate_detection()  # Hash before encryption so we have the plaintext
    |> encrypt_sensitive_value()             # Encrypt sensitive values after hashing
    |> foreign_key_constraint(:entity_id)
  end

  defp validate_identifier_value(changeset) do
    type = get_field(changeset, :type)
    value = get_change(changeset, :value)

    if value do
      case type do
        "phone" -> validate_phone(changeset, value)
        "email" -> validate_email(changeset, value)
        "ssn" -> validate_ssn(changeset, value)
        "website" -> validate_url(changeset, value)
        _ -> changeset
      end
    else
      add_error(changeset, :value, "is required")
    end
  end

  defp validate_phone(changeset, value) do
    if Regex.match?(~r/^\+[1-9]\d{1,14}$/, value) do
      changeset
    else
      add_error(changeset, :value, "must be in E.164 format (e.g., +12025551234)")
    end
  end

  defp validate_email(changeset, value) do
    if Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, value) do
      changeset
      |> update_change(:value, &String.downcase/1)
    else
      add_error(changeset, :value, "must be a valid email address")
    end
  end

  defp validate_ssn(changeset, value) do
    if Regex.match?(~r/^\d{3}-\d{2}-\d{4}$/, value) do
      changeset
    else
      add_error(changeset, :value, "must be in format XXX-XX-XXXX")
    end
  end

  defp validate_url(changeset, value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        changeset
      _ ->
        add_error(changeset, :value, "must be a valid URL")
    end
  end

  defp encrypt_sensitive_value(changeset) do
    type = get_field(changeset, :type)
    value = get_change(changeset, :value)

    if type in @sensitive_types and value do
      # Encrypt sensitive values (SSN, government_id, account_number) using Vault
      encrypted = Conezia.Vault.encrypt(value)

      changeset
      |> put_change(:value_encrypted, encrypted)
      |> put_change(:value, nil)
    else
      changeset
    end
  end

  @doc """
  Decrypt the sensitive value from an identifier.
  Returns nil for non-sensitive types or if decryption fails.
  """
  def decrypt_value(%__MODULE__{type: type, value_encrypted: encrypted}) when type in @sensitive_types do
    case Conezia.Vault.decrypt(encrypted) do
      {:ok, plaintext} -> plaintext
      {:error, _} -> nil
    end
  end
  def decrypt_value(%__MODULE__{value: value}), do: value

  defp hash_value_for_duplicate_detection(changeset) do
    type = get_field(changeset, :type)
    value = get_change(changeset, :value)

    if value do
      # Use blind index for consistent, searchable hashing
      # This is called before encryption, so value is still plaintext
      hash = Conezia.Vault.blind_index(value, "identifier_#{type}")
      put_change(changeset, :value_hash, hash)
    else
      changeset
    end
  end

  def sensitive_type?(type), do: type in @sensitive_types
  def valid_types, do: @identifier_types
end
