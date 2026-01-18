defmodule Conezia.Workers.SyncWorker do
  @moduledoc """
  Oban worker for syncing contacts from external services.

  This worker fetches contacts from connected external services (e.g., Google Contacts)
  and imports them into the user's connections.
  """
  use Oban.Worker, queue: :sync, max_attempts: 3

  alias Conezia.Imports
  alias Conezia.Imports.ImportJob
  alias Conezia.ExternalAccounts
  alias Conezia.Integrations
  alias Conezia.Integrations.ServiceProvider
  alias Conezia.Entities
  alias Conezia.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_job_id" => import_job_id}}) do
    case Repo.get(ImportJob, import_job_id) |> Repo.preload(:external_account) do
      nil ->
        {:error, :import_job_not_found}

      %ImportJob{status: "completed"} ->
        :ok

      %ImportJob{status: "failed"} ->
        :ok

      %ImportJob{external_account: nil} ->
        {:error, :no_external_account}

      import_job ->
        process_sync(import_job)
    end
  end

  defp process_sync(import_job) do
    {:ok, import_job} = Imports.start_import(import_job)

    try do
      account = import_job.external_account

      with {:ok, refreshed_account} <- Integrations.refresh_tokens_if_needed(account),
           {:ok, provider} <- ServiceProvider.get_provider(refreshed_account.service_name),
           {:ok, access_token} <- Integrations.get_access_token(refreshed_account) do
        result = fetch_and_import_contacts(import_job, provider, access_token)

        case result do
          {:ok, stats} ->
            ExternalAccounts.mark_synced(refreshed_account)
            Imports.complete_import(import_job, stats)
            :ok

          {:error, errors} when is_list(errors) ->
            ExternalAccounts.mark_error(refreshed_account, "Sync failed")
            Imports.fail_import(import_job, errors)
            {:error, errors}

          {:error, error} ->
            ExternalAccounts.mark_error(refreshed_account, to_string(error))
            Imports.fail_import(import_job, [%{message: to_string(error)}])
            {:error, error}
        end
      else
        {:error, reason} ->
          Imports.fail_import(import_job, [%{message: to_string(reason)}])
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Sync worker error: #{Exception.message(e)}")
        Imports.fail_import(import_job, [%{message: Exception.message(e)}])
        {:error, e}
    end
  end

  defp fetch_and_import_contacts(import_job, provider, access_token) do
    fetch_all_contacts(provider, access_token, nil, [])
    |> case do
      {:ok, contacts} ->
        import_contacts(import_job, contacts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all_contacts(provider, access_token, page_token, accumulated) do
    opts = if page_token, do: [page_token: page_token], else: []

    case provider.fetch_contacts(access_token, opts) do
      {:ok, contacts, nil} ->
        {:ok, accumulated ++ contacts}

      {:ok, contacts, next_page_token} ->
        fetch_all_contacts(provider, access_token, next_page_token, accumulated ++ contacts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_contacts(import_job, contacts) do
    total = length(contacts)

    stats =
      Enum.reduce(contacts, %{created: 0, merged: 0, skipped: 0, errors: []}, fn contact, acc ->
        case import_contact(import_job.user_id, contact) do
          {:ok, :created} -> %{acc | created: acc.created + 1}
          {:ok, :merged} -> %{acc | merged: acc.merged + 1}
          {:ok, :skipped} -> %{acc | skipped: acc.skipped + 1}
          {:error, reason} -> %{acc | errors: [%{contact: contact.name, error: reason} | acc.errors]}
        end
      end)

    {:ok,
     %{
       total_records: total,
       processed_records: total,
       created_records: stats.created,
       merged_records: stats.merged,
       skipped_records: stats.skipped,
       error_log: Enum.take(stats.errors, 100)
     }}
  end

  defp import_contact(user_id, contact) do
    # Skip contacts without names
    if is_nil(contact.name) or contact.name == "" do
      {:ok, :skipped}
    else
      # Check for existing entity by email or external_id
      case find_existing_entity(user_id, contact) do
        nil ->
          create_entity(user_id, contact)

        existing ->
          merge_entity(existing, contact)
      end
    end
  end

  defp find_existing_entity(user_id, contact) do
    # First try to find by external_id
    case contact.external_id do
      nil -> nil
      external_id ->
        Entities.find_by_external_id(user_id, external_id)
    end
    |> case do
      nil ->
        # Try to find by email
        case contact.email do
          nil -> nil
          email -> Entities.find_by_email(user_id, email)
        end

      entity ->
        entity
    end
  end

  defp create_entity(user_id, contact) do
    attrs = %{
      "name" => contact.name,
      "type" => "person",
      "owner_id" => user_id,
      "description" => contact.organization,
      "notes" => contact.notes,
      "metadata" => contact.metadata || %{}
    }

    case Entities.create_entity(attrs) do
      {:ok, entity} ->
        create_identifiers(entity, contact)
        {:ok, :created}

      {:error, _changeset} ->
        {:error, "Failed to create entity"}
    end
  end

  defp merge_entity(existing, contact) do
    # Update entity with new data if relevant
    updates = %{}

    updates =
      if contact.organization && is_nil(existing.description) do
        Map.put(updates, "description", contact.organization)
      else
        updates
      end

    updates =
      if contact.notes && is_nil(existing.notes) do
        Map.put(updates, "notes", contact.notes)
      else
        updates
      end

    if map_size(updates) > 0 do
      Entities.update_entity(existing, updates)
    end

    # Add any new identifiers
    create_identifiers(existing, contact)

    {:ok, :merged}
  end

  defp create_identifiers(entity, contact) do
    # Add email identifier if not already present
    if contact.email do
      unless Entities.has_identifier?(entity.id, "email", contact.email) do
        Entities.create_identifier(%{
          "entity_id" => entity.id,
          "type" => "email",
          "value" => contact.email,
          "is_primary" => !Entities.has_identifier_type?(entity.id, "email")
        })
      end
    end

    # Add phone identifier if not already present
    if contact.phone do
      unless Entities.has_identifier?(entity.id, "phone", contact.phone) do
        Entities.create_identifier(%{
          "entity_id" => entity.id,
          "type" => "phone",
          "value" => contact.phone,
          "is_primary" => !Entities.has_identifier_type?(entity.id, "phone")
        })
      end
    end
  end
end
