defmodule Conezia.Storage do
  @moduledoc """
  Storage behaviour and abstraction for file uploads.

  Provides a unified interface for storing files that can be backed by
  different storage implementations (local filesystem, S3, GCS, etc.).

  Configure the storage backend in config:

      config :conezia, Conezia.Storage,
        adapter: Conezia.Storage.Local,
        base_path: "priv/uploads"

  Or for S3:

      config :conezia, Conezia.Storage,
        adapter: Conezia.Storage.S3,
        bucket: "my-bucket",
        region: "us-east-1"
  """

  @type storage_key :: String.t()
  @type upload :: %Plug.Upload{} | %{path: String.t(), filename: String.t()}
  @type metadata :: map()

  @doc """
  Store a file and return a storage key.
  """
  @callback store(upload(), metadata()) :: {:ok, storage_key()} | {:error, term()}

  @doc """
  Retrieve a file by its storage key.
  Returns the file content as binary.
  """
  @callback get(storage_key()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Delete a file by its storage key.
  """
  @callback delete(storage_key()) :: :ok | {:error, term()}

  @doc """
  Check if a file exists.
  """
  @callback exists?(storage_key()) :: boolean()

  @doc """
  Generate a signed URL for downloading a file.
  The URL expires after the specified number of seconds.
  """
  @callback signed_url(storage_key(), expires_in :: integer()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Get the public URL for a file (if publicly accessible).
  """
  @callback public_url(storage_key()) :: {:ok, String.t()} | {:error, :not_public}

  # Convenience functions that delegate to the configured adapter

  defp adapter do
    Application.get_env(:conezia, __MODULE__, [])[:adapter] || Conezia.Storage.Local
  end

  @doc """
  Store a file using the configured adapter.
  """
  def store(upload, metadata \\ %{}) do
    adapter().store(upload, metadata)
  end

  @doc """
  Get a file using the configured adapter.
  """
  def get(storage_key) do
    adapter().get(storage_key)
  end

  @doc """
  Delete a file using the configured adapter.
  """
  def delete(storage_key) do
    adapter().delete(storage_key)
  end

  @doc """
  Check if a file exists using the configured adapter.
  """
  def exists?(storage_key) do
    adapter().exists?(storage_key)
  end

  @doc """
  Generate a signed URL using the configured adapter.
  """
  def signed_url(storage_key, expires_in \\ 3600) do
    adapter().signed_url(storage_key, expires_in)
  end

  @doc """
  Get the public URL using the configured adapter.
  """
  def public_url(storage_key) do
    adapter().public_url(storage_key)
  end

  @doc """
  Generate a unique storage key for a file.
  """
  def generate_key(filename, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "uploads")
    user_id = Keyword.get(opts, :user_id)
    date = Date.utc_today()

    # Sanitize filename
    safe_filename = filename
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.slice(0, 100)

    uuid = UUID.uuid4()

    parts = [prefix]
    parts = if user_id, do: parts ++ [user_id], else: parts
    parts = parts ++ ["#{date.year}", "#{date.month}", "#{date.day}"]
    parts = parts ++ ["#{uuid}_#{safe_filename}"]

    Enum.join(parts, "/")
  end
end
