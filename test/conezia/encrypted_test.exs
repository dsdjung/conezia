defmodule Conezia.EncryptedTest do
  use ExUnit.Case, async: true

  alias Conezia.Encrypted.{Binary, Map}

  describe "Conezia.Encrypted.Binary" do
    test "type/0 returns :binary" do
      assert Binary.type() == :binary
    end

    test "cast/1 accepts nil" do
      assert Binary.cast(nil) == {:ok, nil}
    end

    test "cast/1 accepts binary strings" do
      assert Binary.cast("secret_token") == {:ok, "secret_token"}
    end

    test "cast/1 rejects non-binary values" do
      assert Binary.cast(123) == :error
      assert Binary.cast(%{}) == :error
      assert Binary.cast([]) == :error
    end

    test "dump/1 encrypts the value" do
      {:ok, encrypted} = Binary.dump("my_secret")
      assert is_binary(encrypted)
      assert encrypted != "my_secret"
      # Encrypted value should be base64
      assert {:ok, _} = Base.decode64(encrypted)
    end

    test "dump/1 handles nil" do
      assert Binary.dump(nil) == {:ok, nil}
    end

    test "dump/1 handles empty string" do
      assert Binary.dump("") == {:ok, ""}
    end

    test "load/1 decrypts the value" do
      {:ok, encrypted} = Binary.dump("my_secret")
      {:ok, decrypted} = Binary.load(encrypted)
      assert decrypted == "my_secret"
    end

    test "load/1 handles nil" do
      assert Binary.load(nil) == {:ok, nil}
    end

    test "load/1 handles empty string" do
      assert Binary.load("") == {:ok, ""}
    end

    test "load/1 returns nil for invalid encrypted data" do
      {:ok, result} = Binary.load("not_encrypted_data")
      assert result == nil
    end

    test "round-trip encryption preserves data" do
      original = "super_secret_token_12345"
      {:ok, encrypted} = Binary.dump(original)
      {:ok, decrypted} = Binary.load(encrypted)
      assert decrypted == original
    end

    test "same value encrypts to different ciphertexts (unique IVs)" do
      {:ok, encrypted1} = Binary.dump("same_value")
      {:ok, encrypted2} = Binary.dump("same_value")
      assert encrypted1 != encrypted2
    end

    test "equal?/2 compares values correctly" do
      assert Binary.equal?(nil, nil) == true
      assert Binary.equal?("a", "a") == true
      assert Binary.equal?("a", "b") == false
    end
  end

  describe "Conezia.Encrypted.Map" do
    test "type/0 returns :binary" do
      assert Map.type() == :binary
    end

    test "cast/1 accepts nil" do
      assert Map.cast(nil) == {:ok, nil}
    end

    test "cast/1 accepts maps" do
      map = %{"key" => "value", "nested" => %{"inner" => 123}}
      assert Map.cast(map) == {:ok, map}
    end

    test "cast/1 accepts JSON strings" do
      json = ~s({"key": "value"})
      assert Map.cast(json) == {:ok, %{"key" => "value"}}
    end

    test "cast/1 rejects invalid values" do
      assert Map.cast(123) == :error
      assert Map.cast([]) == :error
      assert Map.cast("not json") == :error
    end

    test "dump/1 encrypts the map as JSON" do
      map = %{"api_key" => "secret123", "settings" => %{"enabled" => true}}
      {:ok, encrypted} = Map.dump(map)
      assert is_binary(encrypted)
      # Should not be readable JSON
      assert {:error, _} = Jason.decode(encrypted)
      # Should be base64 encoded
      assert {:ok, _} = Base.decode64(encrypted)
    end

    test "dump/1 handles nil" do
      assert Map.dump(nil) == {:ok, nil}
    end

    test "load/1 decrypts to a map" do
      map = %{"api_key" => "secret123", "count" => 42}
      {:ok, encrypted} = Map.dump(map)
      {:ok, decrypted} = Map.load(encrypted)
      assert decrypted == map
    end

    test "load/1 handles nil" do
      assert Map.load(nil) == {:ok, nil}
    end

    test "load/1 handles empty string" do
      assert Map.load("") == {:ok, %{}}
    end

    test "load/1 returns nil for invalid encrypted data" do
      {:ok, result} = Map.load("not_encrypted")
      assert result == nil
    end

    test "round-trip encryption preserves complex maps" do
      original = %{
        "credentials" => %{
          "access_key" => "AKIA...",
          "secret_key" => "wJalr..."
        },
        "settings" => %{
          "region" => "us-east-1",
          "timeout" => 30
        },
        "tags" => ["production", "primary"]
      }
      {:ok, encrypted} = Map.dump(original)
      {:ok, decrypted} = Map.load(encrypted)
      assert decrypted == original
    end

    test "equal?/2 compares values correctly" do
      assert Map.equal?(nil, nil) == true
      assert Map.equal?(%{"a" => 1}, %{"a" => 1}) == true
      assert Map.equal?(%{"a" => 1}, %{"a" => 2}) == false
      assert Map.equal?(%{"a" => 1}, nil) == false
    end
  end
end
