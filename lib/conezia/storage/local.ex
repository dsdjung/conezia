defmodule Conezia.Storage.Local do
  @moduledoc """
  Local filesystem storage adapter.

  Stores files in a local directory. Suitable for development
  and small-scale deployments.

  Configuration:

      config :conezia, Conezia.Storage,
        adapter: Conezia.Storage.Local,
        base_path: "priv/uploads"
  """

  @behaviour Conezia.Storage

  defp base_path do
    Application.get_env(:conezia, Conezia.Storage, [])[:base_path] || "priv/uploads"
  end

  @impl true
  def store(upload, metadata \\ %{}) do
    filename = get_filename(upload)
    storage_key = Conezia.Storage.generate_key(filename, Map.to_list(metadata))

    case safe_path(storage_key) do
      {:ok, dest_path} ->
        dest_dir = Path.dirname(dest_path)

        with :ok <- File.mkdir_p(dest_dir),
             :ok <- copy_file(upload, dest_path) do
          {:ok, storage_key}
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, :path_traversal} ->
        {:error, :invalid_storage_key}
    end
  end

  # Validate that the storage key doesn't attempt path traversal
  defp safe_path(storage_key) do
    # Reject any path traversal attempts
    if String.contains?(storage_key, "..") or
       String.starts_with?(storage_key, "/") or
       String.contains?(storage_key, "\0") do
      {:error, :path_traversal}
    else
      base = Path.expand(base_path())
      full_path = Path.expand(Path.join(base, storage_key))

      # Ensure the expanded path is still within base_path
      if String.starts_with?(full_path, base <> "/") or full_path == base do
        {:ok, full_path}
      else
        {:error, :path_traversal}
      end
    end
  end

  defp get_filename(%Plug.Upload{filename: filename}), do: filename
  defp get_filename(%{filename: filename}), do: filename
  defp get_filename(_), do: "unknown"

  defp copy_file(%Plug.Upload{path: source_path}, dest_path) do
    File.cp(source_path, dest_path)
  end

  defp copy_file(%{path: source_path}, dest_path) do
    File.cp(source_path, dest_path)
  end

  @impl true
  def get(storage_key) do
    case safe_path(storage_key) do
      {:ok, path} ->
        case File.read(path) do
          {:ok, content} -> {:ok, content}
          {:error, :enoent} -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end

      {:error, :path_traversal} ->
        {:error, :invalid_storage_key}
    end
  end

  @impl true
  def delete(storage_key) do
    case safe_path(storage_key) do
      {:ok, path} ->
        case File.rm(path) do
          :ok -> :ok
          {:error, :enoent} -> :ok  # Already deleted
          {:error, reason} -> {:error, reason}
        end

      {:error, :path_traversal} ->
        {:error, :invalid_storage_key}
    end
  end

  @impl true
  def exists?(storage_key) do
    case safe_path(storage_key) do
      {:ok, path} -> File.exists?(path)
      {:error, :path_traversal} -> false
    end
  end

  @impl true
  def signed_url(storage_key, expires_in) do
    # For local storage, we generate a simple signed URL using HMAC
    # In production, you might want a more sophisticated approach
    secret = Application.get_env(:conezia, ConeziaWeb.Endpoint)[:secret_key_base]
    expires_at = System.system_time(:second) + expires_in

    signature_data = "#{storage_key}:#{expires_at}"
    signature = :crypto.mac(:hmac, :sha256, secret, signature_data)
    |> Base.url_encode64(padding: false)

    url = "/api/v1/attachments/download?" <>
      URI.encode_query(%{
        key: storage_key,
        expires: expires_at,
        sig: signature
      })

    {:ok, url}
  end

  @impl true
  def public_url(_storage_key) do
    # Local storage is not publicly accessible
    {:error, :not_public}
  end

  @doc """
  Verify a signed URL is valid.
  """
  def verify_signature(storage_key, expires_at, signature) do
    secret = Application.get_env(:conezia, ConeziaWeb.Endpoint)[:secret_key_base]

    # Check expiration
    if System.system_time(:second) > expires_at do
      {:error, :expired}
    else
      signature_data = "#{storage_key}:#{expires_at}"
      expected_sig = :crypto.mac(:hmac, :sha256, secret, signature_data)
      |> Base.url_encode64(padding: false)

      if Plug.Crypto.secure_compare(expected_sig, signature) do
        :ok
      else
        {:error, :invalid_signature}
      end
    end
  end

  @doc """
  Get the full file path for a storage key.
  Returns {:ok, path} or {:error, :invalid_storage_key} if path traversal is detected.
  """
  def file_path(storage_key) do
    safe_path(storage_key)
  end
end
