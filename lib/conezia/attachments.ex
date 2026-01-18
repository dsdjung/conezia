defmodule Conezia.Attachments do
  @moduledoc """
  The Attachments context for managing file uploads.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Attachments.Attachment

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
    attachment
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
    |> Repo.update()
  end

  def delete_attachment(%Attachment{} = attachment) do
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

  def create_attachment(attrs, %Plug.Upload{} = upload) do
    # Store the file (in production, this would upload to S3/GCS)
    storage_key = store_file(upload)

    attrs = Map.put(attrs, :storage_key, storage_key)

    %Attachment{}
    |> Attachment.changeset(attrs)
    |> Repo.insert()
  end

  defp store_file(%Plug.Upload{path: path, filename: filename}) do
    # In production, upload to cloud storage
    # For now, copy to local storage
    upload_dir = Path.join(["priv", "uploads"])
    File.mkdir_p!(upload_dir)

    storage_key = "#{UUID.uuid4()}_#{filename}"
    dest_path = Path.join(upload_dir, storage_key)

    File.cp!(path, dest_path)
    storage_key
  end

  def get_download_url(%Attachment{storage_key: nil}), do: {:error, :file_not_found}
  def get_download_url(%Attachment{storage_key: key}) do
    path = Path.join(["priv", "uploads", key])
    if File.exists?(path) do
      {:ok, "/api/v1/attachments/#{key}/download"}
    else
      {:error, :file_not_found}
    end
  end
end
