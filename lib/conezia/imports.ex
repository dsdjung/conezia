defmodule Conezia.Imports do
  @moduledoc """
  The Imports context for managing contact import jobs.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Imports.ImportJob

  def get_import_job(id), do: Repo.get(ImportJob, id)

  def get_import_job!(id), do: Repo.get!(ImportJob, id)

  def get_import_job_for_user(id, user_id) do
    ImportJob
    |> where([ij], ij.id == ^id and ij.user_id == ^user_id)
    |> Repo.one()
  end

  def list_import_jobs(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    status = Keyword.get(opts, :status)

    query = from ij in ImportJob,
      where: ij.user_id == ^user_id,
      limit: ^limit,
      order_by: [desc: ij.inserted_at]

    query
    |> filter_by_status(status)
    |> Repo.all()
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: where(query, [ij], ij.status == ^status)

  def create_import_job(attrs) do
    %ImportJob{}
    |> ImportJob.changeset(attrs)
    |> Repo.insert()
  end

  def start_import_job(%ImportJob{} = import_job) do
    import_job
    |> ImportJob.start_changeset()
    |> Repo.update()
  end

  # Alias for worker compatibility
  def start_import(%ImportJob{} = import_job), do: start_import_job(import_job)

  def complete_import_job(%ImportJob{} = import_job, stats) do
    import_job
    |> ImportJob.complete_changeset(stats)
    |> Repo.update()
  end

  # Alias for worker compatibility
  def complete_import(%ImportJob{} = import_job, stats), do: complete_import_job(import_job, stats)

  def fail_import_job(%ImportJob{} = import_job, errors) do
    import_job
    |> ImportJob.fail_changeset(errors)
    |> Repo.update()
  end

  # Alias for worker compatibility
  def fail_import(%ImportJob{} = import_job, errors), do: fail_import_job(import_job, errors)

  def cancel_import_job(%ImportJob{status: "pending"} = import_job) do
    import_job
    |> Ecto.Changeset.change(status: "cancelled")
    |> Repo.update()
  end

  def cancel_import_job(%ImportJob{}), do: {:error, "Cannot cancel import job that is not pending"}

  def confirm_import_job(%ImportJob{} = import_job, _opts) do
    # In production, this would start processing the import
    import_job
    |> ImportJob.start_changeset()
    |> Repo.update()
  end

  def export_data(_user_id, format, _entity_ids, _include) when format not in ["csv", "json", "vcard"] do
    {:error, "Unsupported export format"}
  end

  def export_data(_user_id, _format, _entity_ids, _include) do
    # In production, this would generate an export file
    download_url = "/api/v1/exports/#{UUID.uuid4()}"
    expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)
    {:ok, download_url, expires_at}
  end
end
