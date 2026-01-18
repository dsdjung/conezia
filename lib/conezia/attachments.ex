defmodule Conezia.Attachments do
  @moduledoc """
  The Attachments context for managing file uploads.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Attachments.Attachment
  alias Conezia.Storage

  def get_attachment(id), do: Repo.get(Attachment, id)

  def get_attachment!(id), do: Repo.get!(Attachment, id)

  def get_attachment_for_user(id, user_id) do
    Attachment
    |> where([a], a.id == ^id and a.user_id == ^user_id and is_nil(a.deleted_at))
    |> Repo.one()
  end

  def list_attachments_for_entity(entity_id) do
    Attachment
    |> where([a], a.entity_id == ^entity_id and is_nil(a.deleted_at))
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  def list_attachments_for_interaction(interaction_id) do
    Attachment
    |> where([a], a.interaction_id == ^interaction_id and is_nil(a.deleted_at))
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  def create_attachment(attrs) do
    %Attachment{}
    |> Attachment.changeset(attrs)
    |> Repo.insert()
  end

  def soft_delete_attachment(%Attachment{} = attachment) do
    # Also delete from storage
    if attachment.storage_key do
      Storage.delete(attachment.storage_key)
    end

    attachment
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
    |> Repo.update()
  end

  def delete_attachment(%Attachment{} = attachment) do
    # Delete from storage first
    if attachment.storage_key do
      Storage.delete(attachment.storage_key)
    end

    Repo.delete(attachment)
  end

  def list_attachments_for_entity(entity_id, opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)

    attachments = Attachment
    |> where([a], a.entity_id == ^entity_id and is_nil(a.deleted_at))
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()

    {attachments, %{has_more: false, next_cursor: nil}}
  end

  @doc """
  Create an attachment with file upload.
  Uses the configured storage adapter (local or S3).
  """
  def create_attachment(attrs, %Plug.Upload{} = upload) do
    metadata = %{user_id: attrs["user_id"] || attrs[:user_id]}

    case Storage.store(upload, metadata) do
      {:ok, storage_key} ->
        attrs = attrs
        |> Map.put("storage_key", storage_key)
        |> Map.put("filename", upload.filename)
        |> Map.put("mime_type", upload.content_type)
        |> Map.put("size_bytes", get_file_size(upload))

        %Attachment{}
        |> Attachment.changeset(attrs)
        |> Repo.insert()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_file_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  @doc """
  Get a signed download URL for an attachment.
  The URL expires after the specified number of seconds (default: 1 hour).
  """
  def get_download_url(%Attachment{storage_key: nil}), do: {:error, :file_not_found}
  def get_download_url(%Attachment{storage_key: key}, expires_in \\ 3600) do
    if Storage.exists?(key) do
      Storage.signed_url(key, expires_in)
    else
      {:error, :file_not_found}
    end
  end

  @doc """
  Get the raw file content for an attachment.
  """
  def get_file_content(%Attachment{storage_key: nil}), do: {:error, :file_not_found}
  def get_file_content(%Attachment{storage_key: key}) do
    Storage.get(key)
  end

  @doc """
  Check if an attachment's file exists in storage.
  """
  def file_exists?(%Attachment{storage_key: nil}), do: false
  def file_exists?(%Attachment{storage_key: key}), do: Storage.exists?(key)
end
