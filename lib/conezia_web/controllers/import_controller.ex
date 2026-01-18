defmodule ConeziaWeb.ImportController do
  @moduledoc """
  Controller for import/export endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Imports
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  POST /api/v1/import
  Start a new import job.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    attrs =
      case params["file"] do
        %Plug.Upload{} = upload ->
          %{
            user_id: user.id,
            source: params["source"] || "csv",
            file_path: upload.path,
            original_filename: upload.filename,
            status: "pending"
          }

        nil ->
          %{
            user_id: user.id,
            source: params["source"],
            oauth_token: params["oauth_token"],
            status: "pending"
          }
      end

    case Imports.create_import_job(attrs) do
      {:ok, job} ->
        conn
        |> put_status(:accepted)
        |> json(%{
          data: %{
            job_id: job.id,
            status: job.status,
            source: job.source
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  GET /api/v1/import/:job_id
  Get the status of an import job.
  """
  def show(conn, %{"job_id" => job_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Imports.get_import_job_for_user(job_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("import job", job_id, conn.request_path))

      job ->
        conn
        |> put_status(:ok)
        |> json(%{data: import_job_json(job)})
    end
  end

  @doc """
  POST /api/v1/import/:job_id/confirm
  Confirm and process an import job.
  """
  def confirm(conn, %{"job_id" => job_id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Imports.get_import_job_for_user(job_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("import job", job_id, conn.request_path))

      job ->
        opts = %{
          merge_strategy: params["merge_strategy"] || "skip_duplicates",
          field_mapping: params["field_mapping"] || %{}
        }

        case Imports.confirm_import_job(job, opts) do
          {:ok, updated_job} ->
            conn
            |> put_status(:ok)
            |> json(%{data: import_job_json(updated_job)})

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/import/:job_id
  Cancel an import job.
  """
  def delete(conn, %{"job_id" => job_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Imports.get_import_job_for_user(job_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("import job", job_id, conn.request_path))

      job ->
        case Imports.cancel_import_job(job) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Import job cancelled"}})

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  GET /api/v1/export
  Export data in various formats.
  """
  def export(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    format = params["format"] || "json"
    entity_ids = params["entity_ids"]
    include = params["include"] || "identifiers"

    case Imports.export_data(user.id, format, entity_ids, include) do
      {:ok, download_url, expires_at} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: %{
            download_url: download_url,
            expires_at: expires_at
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request(reason, conn.request_path))
    end
  end

  # Private helpers

  defp import_job_json(job) do
    base = %{
      id: job.id,
      status: job.status,
      source: job.source,
      started_at: job.started_at,
      completed_at: job.completed_at
    }

    if job.progress do
      Map.put(base, :progress, %{
        total_records: job.progress["total_records"],
        processed_records: job.progress["processed_records"],
        created_records: job.progress["created_records"],
        merged_records: job.progress["merged_records"],
        skipped_records: job.progress["skipped_records"]
      })
    else
      base
    end
  end
end
