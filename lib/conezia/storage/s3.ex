defmodule Conezia.Storage.S3 do
  @moduledoc """
  S3-compatible storage adapter.

  Stores files in AWS S3 or S3-compatible services (MinIO, DigitalOcean Spaces, etc.).

  Configuration:

      config :conezia, Conezia.Storage,
        adapter: Conezia.Storage.S3,
        bucket: "my-bucket",
        region: "us-east-1",
        access_key_id: "...",
        secret_access_key: "...",
        host: "s3.amazonaws.com"  # or custom endpoint for S3-compatible services

  Note: This is a placeholder implementation. In production, you would use
  a library like ExAws or aws_s3 for actual S3 operations.
  """

  @behaviour Conezia.Storage

  defp config do
    Application.get_env(:conezia, Conezia.Storage, [])
  end

  defp bucket, do: config()[:bucket]
  defp region, do: config()[:region] || "us-east-1"
  defp host, do: config()[:host] || "s3.#{region()}.amazonaws.com"

  @impl true
  def store(upload, metadata \\ %{}) do
    filename = get_filename(upload)
    storage_key = Conezia.Storage.generate_key(filename, Map.to_list(metadata))

    content_type = get_content_type(upload)
    body = read_file(upload)

    put_object(storage_key, body, content_type)
  end

  defp get_filename(%Plug.Upload{filename: filename}), do: filename
  defp get_filename(%{filename: filename}), do: filename
  defp get_filename(_), do: "unknown"

  defp get_content_type(%Plug.Upload{content_type: ct}) when is_binary(ct), do: ct
  defp get_content_type(%{content_type: ct}) when is_binary(ct), do: ct
  defp get_content_type(_), do: "application/octet-stream"

  defp read_file(%Plug.Upload{path: path}), do: File.read!(path)
  defp read_file(%{path: path}), do: File.read!(path)

  @spec put_object(String.t(), binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp put_object(key, _body, _content_type) do
    # Placeholder: In production, use ExAws or similar
    # case ExAws.S3.put_object(bucket(), key, body, content_type: content_type) |> ExAws.request() do
    #   {:ok, _} -> {:ok, key}
    #   {:error, reason} -> {:error, reason}
    # end
    {:error, {:s3_not_configured, key}}
  end

  @impl true
  def get(storage_key) do
    get_object(storage_key)
  end

  @spec get_object(String.t()) :: {:ok, binary()} | {:error, term()}
  defp get_object(_key) do
    # Placeholder: In production, use ExAws or similar
    # case ExAws.S3.get_object(bucket(), key) |> ExAws.request() do
    #   {:ok, %{body: body}} -> {:ok, body}
    #   {:error, reason} -> {:error, reason}
    # end
    {:error, :s3_not_configured}
  end

  @impl true
  def delete(storage_key) do
    delete_object(storage_key)
  end

  @spec delete_object(String.t()) :: :ok | {:error, term()}
  defp delete_object(_key) do
    # Placeholder: In production, use ExAws or similar
    # case ExAws.S3.delete_object(bucket(), key) |> ExAws.request() do
    #   {:ok, _} -> :ok
    #   {:error, reason} -> {:error, reason}
    # end
    {:error, :s3_not_configured}
  end

  @impl true
  def exists?(_storage_key) do
    # Placeholder: Always returns false until S3 is configured
    # In production, this would check head_object
    false
  end

  @impl true
  def signed_url(storage_key, expires_in) do
    # Generate a presigned URL for S3
    # This is a simplified version - in production use ExAws.S3.presigned_url
    expires_at = DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.to_iso8601()

    # Placeholder URL - in production this would be a real presigned URL
    url = "https://#{bucket()}.#{host()}/#{storage_key}?X-Amz-Expires=#{expires_in}&X-Amz-Date=#{expires_at}"

    {:ok, url}
  end

  @impl true
  def public_url(storage_key) do
    url = "https://#{bucket()}.#{host()}/#{storage_key}"
    {:ok, url}
  end
end
