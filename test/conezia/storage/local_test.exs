defmodule Conezia.Storage.LocalTest do
  use ExUnit.Case, async: true

  alias Conezia.Storage.Local

  describe "safe_path/1 via file_path/1" do
    test "accepts valid storage keys" do
      assert {:ok, _path} = Local.file_path("abc123.jpg")
      assert {:ok, _path} = Local.file_path("2024/01/15/abc123.jpg")
      assert {:ok, _path} = Local.file_path("user_uploads/document.pdf")
    end

    test "rejects path traversal with .." do
      assert {:error, :path_traversal} = Local.file_path("../etc/passwd")
      assert {:error, :path_traversal} = Local.file_path("foo/../../../etc/passwd")
      assert {:error, :path_traversal} = Local.file_path("uploads/..hidden/file.txt")
    end

    test "rejects absolute paths" do
      assert {:error, :path_traversal} = Local.file_path("/etc/passwd")
      assert {:error, :path_traversal} = Local.file_path("/var/log/syslog")
    end

    test "rejects null bytes" do
      assert {:error, :path_traversal} = Local.file_path("file.jpg\0.txt")
      assert {:error, :path_traversal} = Local.file_path("uploads/\0/secret")
    end
  end

  describe "exists?/1" do
    test "returns false for path traversal attempts" do
      refute Local.exists?("../etc/passwd")
      refute Local.exists?("/etc/passwd")
    end
  end
end
