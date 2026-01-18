defmodule ConeziaWeb.AttachmentController do
  @moduledoc """
  Controller for attachment management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Attachments
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  POST /api/v1/attachments
  Upload a new attachment.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    case params["file"] do
      %Plug.Upload{} = upload ->
        attrs = %{
          user_id: user.id,
          entity_id: params["entity_id"],
          interaction_id: params["interaction_id"],
          communication_id: params["communication_id"],
          filename: upload.filename,
          mime_type: upload.content_type,
          size_bytes: get_file_size(upload.path)
        }

        case Attachments.create_attachment(attrs, upload) do
          {:ok, attachment} ->
            conn
            |> put_status(:created)
            |> json(%{data: attachment_json(attachment)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end

      nil ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request("file is required.", conn.request_path))
    end
  end

  @doc """
  GET /api/v1/attachments/:id
  Get attachment metadata.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Attachments.get_attachment_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("attachment", id, conn.request_path))

      attachment ->
        conn
        |> put_status(:ok)
        |> json(%{data: attachment_json(attachment)})
    end
  end

  @doc """
  GET /api/v1/attachments/:id/download
  Download an attachment.
  """
  def download(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Attachments.get_attachment_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("attachment", id, conn.request_path))

      attachment ->
        case Attachments.get_download_url(attachment) do
          {:ok, url} ->
            conn
            |> put_resp_header("location", url)
            |> send_resp(:found, "")

          {:error, :file_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(ErrorHelpers.not_found("attachment file", id, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/attachments/:id
  Delete an attachment.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Attachments.get_attachment_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("attachment", id, conn.request_path))

      attachment ->
        case Attachments.delete_attachment(attachment) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Attachment deleted"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  # Private helpers

  defp get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp attachment_json(attachment) do
    %{
      id: attachment.id,
      filename: attachment.filename,
      mime_type: attachment.mime_type,
      size_bytes: attachment.size_bytes,
      download_url: "/api/v1/attachments/#{attachment.id}/download",
      inserted_at: attachment.inserted_at
    }
  end
end
