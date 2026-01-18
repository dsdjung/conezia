defmodule Conezia.StorageTest do
  use ExUnit.Case, async: true

  alias Conezia.Storage
  alias Conezia.Storage.Local

  @test_upload_dir "test/support/test_uploads"

  setup do
    # Create test upload directory
    File.mkdir_p!(@test_upload_dir)

    # Configure test storage
    Application.put_env(:conezia, Conezia.Storage,
      adapter: Conezia.Storage.Local,
      base_path: @test_upload_dir
    )

    on_exit(fn ->
      # Clean up test files
      File.rm_rf!(@test_upload_dir)
    end)

    :ok
  end

  describe "generate_key/2" do
    test "generates a unique storage key" do
      key = Storage.generate_key("test.txt")

      assert is_binary(key)
      assert String.starts_with?(key, "uploads/")
      assert String.ends_with?(key, "_test.txt")
    end

    test "includes prefix in key" do
      key = Storage.generate_key("test.txt", prefix: "documents")

      assert String.starts_with?(key, "documents/")
    end

    test "includes user_id in key when provided" do
      key = Storage.generate_key("test.txt", user_id: "user-123")

      assert String.contains?(key, "user-123")
    end

    test "sanitizes filename" do
      key = Storage.generate_key("test file!@#$.txt")

      # Special characters should be replaced with underscores
      refute String.contains?(key, "!")
      refute String.contains?(key, "@")
      refute String.contains?(key, "#")
      refute String.contains?(key, "$")
    end

    test "truncates long filenames" do
      long_name = String.duplicate("a", 200) <> ".txt"
      key = Storage.generate_key(long_name)

      # Key should contain truncated filename
      filename_part = key |> String.split("/") |> List.last()
      assert String.length(filename_part) <= 140  # UUID + truncated name
    end
  end

  describe "Local adapter" do
    test "store/2 creates a file" do
      # Create a temp file to upload
      temp_path = Path.join(@test_upload_dir, "temp_upload.txt")
      File.write!(temp_path, "test content")

      upload = %{path: temp_path, filename: "uploaded.txt"}

      {:ok, storage_key} = Local.store(upload)

      assert is_binary(storage_key)
      assert Local.exists?(storage_key)
    end

    test "get/1 retrieves file content" do
      # Create a file directly
      storage_key = "test-file.txt"
      path = Path.join(@test_upload_dir, storage_key)
      File.write!(path, "file content here")

      {:ok, content} = Local.get(storage_key)

      assert content == "file content here"
    end

    test "get/1 returns error for non-existent file" do
      {:error, :not_found} = Local.get("non-existent-file.txt")
    end

    test "delete/1 removes a file" do
      # Create a file
      storage_key = "to-delete.txt"
      path = Path.join(@test_upload_dir, storage_key)
      File.write!(path, "content")

      assert File.exists?(path)

      :ok = Local.delete(storage_key)

      refute File.exists?(path)
    end

    test "delete/1 returns ok for non-existent file" do
      :ok = Local.delete("non-existent.txt")
    end

    test "exists?/1 returns true for existing file" do
      storage_key = "existing-file.txt"
      path = Path.join(@test_upload_dir, storage_key)
      File.write!(path, "content")

      assert Local.exists?(storage_key)
    end

    test "exists?/1 returns false for non-existent file" do
      refute Local.exists?("non-existent.txt")
    end

    test "signed_url/2 generates a URL with expiration" do
      storage_key = "file.txt"

      {:ok, url} = Local.signed_url(storage_key, 3600)

      assert is_binary(url)
      assert String.contains?(url, "key=")
      assert String.contains?(url, "expires=")
      assert String.contains?(url, "sig=")
    end

    test "verify_signature/3 validates correct signature" do
      storage_key = "file.txt"
      expires_at = System.system_time(:second) + 3600

      {:ok, url} = Local.signed_url(storage_key, 3600)

      # Parse the URL to get the signature
      query = URI.parse(url).query |> URI.decode_query()
      signature = query["sig"]

      # Note: This uses the actual expires from signed_url, not our expires_at
      assert :ok = Local.verify_signature(storage_key, String.to_integer(query["expires"]), signature)
    end

    test "verify_signature/3 rejects expired URLs" do
      storage_key = "file.txt"
      past_expires = System.system_time(:second) - 100

      {:error, :expired} = Local.verify_signature(storage_key, past_expires, "any-sig")
    end

    test "public_url/1 returns error for local storage" do
      {:error, :not_public} = Local.public_url("any-key")
    end
  end

  describe "Storage delegation" do
    test "store/2 delegates to configured adapter" do
      temp_path = Path.join(@test_upload_dir, "temp.txt")
      File.write!(temp_path, "content")

      upload = %{path: temp_path, filename: "file.txt"}

      {:ok, key} = Storage.store(upload)
      assert is_binary(key)
    end

    test "get/1 delegates to configured adapter" do
      storage_key = "get-test.txt"
      path = Path.join(@test_upload_dir, storage_key)
      File.write!(path, "get content")

      {:ok, content} = Storage.get(storage_key)
      assert content == "get content"
    end

    test "delete/1 delegates to configured adapter" do
      storage_key = "delete-test.txt"
      path = Path.join(@test_upload_dir, storage_key)
      File.write!(path, "content")

      :ok = Storage.delete(storage_key)
      refute File.exists?(path)
    end

    test "exists?/1 delegates to configured adapter" do
      storage_key = "exists-test.txt"
      path = Path.join(@test_upload_dir, storage_key)
      File.write!(path, "content")

      assert Storage.exists?(storage_key)
      refute Storage.exists?("nonexistent.txt")
    end
  end
end
