defmodule Conezia.VaultTest do
  use ExUnit.Case, async: false

  alias Conezia.Vault

  # Embedded schema for testing encrypt_field/2
  defmodule TestSchema do
    use Ecto.Schema

    embedded_schema do
      field :ssn, :string
    end
  end

  setup do
    # Ensure vault is configured for tests
    Application.put_env(:conezia, Conezia.Vault,
      secret_key: "test_vault_key_32_bytes_exactly!")
    :ok
  end

  describe "encrypt/1" do
    test "encrypts a string value" do
      plaintext = "secret-data-123"
      encrypted = Vault.encrypt(plaintext)

      assert is_binary(encrypted)
      assert encrypted != plaintext
      # Encrypted data is base64 encoded
      assert {:ok, _} = Base.decode64(encrypted)
    end

    test "returns nil for nil input" do
      assert Vault.encrypt(nil) == nil
    end

    test "returns empty string for empty input" do
      assert Vault.encrypt("") == ""
    end

    test "produces different ciphertext for same plaintext (semantic security)" do
      plaintext = "same-data"
      encrypted1 = Vault.encrypt(plaintext)
      encrypted2 = Vault.encrypt(plaintext)

      # Each encryption should produce different output due to random IV
      assert encrypted1 != encrypted2
    end
  end

  describe "decrypt/1" do
    test "decrypts an encrypted value" do
      plaintext = "secret-data-123"
      encrypted = Vault.encrypt(plaintext)

      assert {:ok, decrypted} = Vault.decrypt(encrypted)
      assert decrypted == plaintext
    end

    test "returns {:ok, nil} for nil input" do
      assert {:ok, nil} = Vault.decrypt(nil)
    end

    test "returns {:ok, \"\"} for empty string input" do
      assert {:ok, ""} = Vault.decrypt("")
    end

    test "returns error for invalid base64" do
      assert {:error, :invalid_base64} = Vault.decrypt("not-valid-base64!!!")
    end

    test "returns error for tampered data" do
      encrypted = Vault.encrypt("original")
      # Tamper with the encrypted data
      {:ok, data} = Base.decode64(encrypted)
      tampered = Base.encode64(data <> "extra")

      assert {:error, _} = Vault.decrypt(tampered)
    end
  end

  describe "decrypt!/1" do
    test "returns plaintext on success" do
      plaintext = "secret"
      encrypted = Vault.encrypt(plaintext)

      assert Vault.decrypt!(encrypted) == plaintext
    end

    test "returns nil on error" do
      assert Vault.decrypt!("invalid-data") == nil
    end
  end

  describe "hash/1" do
    test "returns a hex-encoded hash" do
      value = "test-value"
      hash = Vault.hash(value)

      assert is_binary(hash)
      assert String.match?(hash, ~r/^[a-f0-9]{64}$/)
    end

    test "returns nil for nil input" do
      assert Vault.hash(nil) == nil
    end

    test "returns empty string for empty input" do
      assert Vault.hash("") == ""
    end

    test "produces same hash for same input (deterministic)" do
      value = "test-value"
      hash1 = Vault.hash(value)
      hash2 = Vault.hash(value)

      assert hash1 == hash2
    end
  end

  describe "blind_index/2" do
    test "returns a hex-encoded index" do
      value = "test-value"
      index = Vault.blind_index(value, "email")

      assert is_binary(index)
      assert String.match?(index, ~r/^[a-f0-9]{64}$/)
    end

    test "returns nil for nil input" do
      assert Vault.blind_index(nil, "field") == nil
    end

    test "returns empty string for empty input" do
      assert Vault.blind_index("", "field") == ""
    end

    test "produces same index for same input and field" do
      value = "test-value"
      index1 = Vault.blind_index(value, "email")
      index2 = Vault.blind_index(value, "email")

      assert index1 == index2
    end

    test "produces different index for different fields" do
      value = "test-value"
      email_index = Vault.blind_index(value, "email")
      phone_index = Vault.blind_index(value, "phone")

      assert email_index != phone_index
    end
  end

  describe "encrypt_field/2" do
    test "encrypts a changeset field" do
      changeset = Ecto.Changeset.change(%TestSchema{ssn: nil}, %{ssn: "123-45-6789"})
      encrypted_changeset = Vault.encrypt_field(changeset, :ssn)

      encrypted_value = Ecto.Changeset.get_change(encrypted_changeset, :ssn)
      assert encrypted_value != "123-45-6789"
      assert {:ok, "123-45-6789"} = Vault.decrypt(encrypted_value)
    end

    test "does nothing if field is not changed" do
      changeset = Ecto.Changeset.change(%TestSchema{ssn: nil}, %{})
      encrypted_changeset = Vault.encrypt_field(changeset, :ssn)

      assert Ecto.Changeset.get_change(encrypted_changeset, :ssn) == nil
    end
  end

  describe "configured?/0" do
    test "returns true when configured" do
      assert Vault.configured?() == true
    end
  end
end
