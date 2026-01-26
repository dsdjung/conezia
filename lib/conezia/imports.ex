defmodule Conezia.Imports do
  @moduledoc """
  The Imports context for managing contact import jobs.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Imports.ImportJob
  alias Conezia.Imports.DeletedImport

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

  # ============================================================================
  # Deleted Imports - Track deleted entities to prevent re-import
  # ============================================================================

  @doc """
  Records that an entity with the given external IDs was deleted.

  This prevents the entity from being re-imported during future syncs.
  The external_ids should be a map of source => external_id.
  """
  def record_deleted_import(user_id, external_ids, opts \\ []) when is_map(external_ids) do
    entity_name = Keyword.get(opts, :entity_name)
    entity_email = Keyword.get(opts, :entity_email)

    entries =
      external_ids
      |> Enum.map(fn {source, external_id} ->
        %{
          user_id: user_id,
          external_id: external_id,
          source: to_string(source),
          entity_name: entity_name,
          entity_email: entity_email,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      end)

    # Use on_conflict to handle duplicates gracefully
    Repo.insert_all(DeletedImport, entries, on_conflict: :nothing)
    :ok
  end

  @doc """
  Records a single deleted import entry.
  """
  def record_deleted_import(user_id, external_id, source, opts) when is_binary(external_id) do
    attrs = %{
      user_id: user_id,
      external_id: external_id,
      source: to_string(source),
      entity_name: Keyword.get(opts, :entity_name),
      entity_email: Keyword.get(opts, :entity_email)
    }

    %DeletedImport{}
    |> DeletedImport.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Checks if an external ID was previously deleted by the user.
  """
  def is_deleted_import?(user_id, external_id, source) do
    from(di in DeletedImport,
      where: di.user_id == ^user_id and di.external_id == ^external_id and di.source == ^to_string(source)
    )
    |> Repo.exists?()
  end

  @doc """
  Checks if any of the external IDs were previously deleted.

  Takes a map of source => external_id and returns true if any were deleted.
  """
  def any_deleted_import?(user_id, external_ids) when is_map(external_ids) do
    Enum.any?(external_ids, fn {source, external_id} ->
      is_deleted_import?(user_id, external_id, source)
    end)
  end

  @doc """
  Gets all deleted external IDs for a user and source.

  Returns a MapSet for efficient lookups during sync.
  """
  def get_deleted_external_ids(user_id, source) do
    from(di in DeletedImport,
      where: di.user_id == ^user_id and di.source == ^to_string(source),
      select: di.external_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Gets all deleted external IDs for a user across all sources.

  Returns a map of source => MapSet of external_ids for efficient lookups.
  """
  def get_all_deleted_external_ids(user_id) do
    from(di in DeletedImport,
      where: di.user_id == ^user_id,
      select: {di.source, di.external_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {source, _} -> source end, fn {_, id} -> id end)
    |> Enum.map(fn {source, ids} -> {source, MapSet.new(ids)} end)
    |> Map.new()
  end

  @doc """
  Removes a deleted import record, allowing the entity to be re-imported.
  """
  def undelete_import(user_id, external_id, source) do
    from(di in DeletedImport,
      where: di.user_id == ^user_id and di.external_id == ^external_id and di.source == ^to_string(source)
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Lists deleted imports for a user with optional filtering.
  """
  def list_deleted_imports(user_id, opts \\ []) do
    source = Keyword.get(opts, :source)
    limit = Keyword.get(opts, :limit, 100)

    query =
      from(di in DeletedImport,
        where: di.user_id == ^user_id,
        order_by: [desc: di.inserted_at],
        limit: ^limit
      )

    query =
      if source do
        where(query, [di], di.source == ^to_string(source))
      else
        query
      end

    Repo.all(query)
  end
end
