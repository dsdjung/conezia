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

  @pubsub Conezia.PubSub
  @topic_prefix "sync:"

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
    broadcast_status(import_job.user_id, :started, %{import_job_id: import_job.id})

    try do
      account = import_job.external_account

      with {:ok, refreshed_account} <- Integrations.refresh_tokens_if_needed(account),
           {:ok, provider} <- ServiceProvider.get_provider(refreshed_account.service_name),
           {:ok, access_token} <- Integrations.get_access_token(refreshed_account) do
        result = fetch_and_import_contacts(import_job, provider, access_token)

        case result do
          {:ok, stats} ->
            ExternalAccounts.mark_synced(refreshed_account)
            {:ok, completed_job} = Imports.complete_import(import_job, stats)
            broadcast_status(import_job.user_id, :completed, %{
              import_job_id: import_job.id,
              stats: stats,
              account_id: refreshed_account.id
            })
            {:ok, completed_job}
            :ok

          {:error, errors} when is_list(errors) ->
            ExternalAccounts.mark_error(refreshed_account, "Sync failed")
            Imports.fail_import(import_job, errors)
            broadcast_status(import_job.user_id, :failed, %{
              import_job_id: import_job.id,
              error: "Sync failed",
              account_id: refreshed_account.id
            })
            {:error, errors}

          {:error, error} ->
            ExternalAccounts.mark_error(refreshed_account, to_string(error))
            Imports.fail_import(import_job, [%{message: to_string(error)}])
            broadcast_status(import_job.user_id, :failed, %{
              import_job_id: import_job.id,
              error: to_string(error),
              account_id: account.id
            })
            {:error, error}
        end
      else
        {:error, reason} ->
          Imports.fail_import(import_job, [%{message: to_string(reason)}])
          broadcast_status(import_job.user_id, :failed, %{
            import_job_id: import_job.id,
            error: to_string(reason)
          })
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Sync worker error: #{Exception.message(e)}")
        Imports.fail_import(import_job, [%{message: Exception.message(e)}])
        broadcast_status(import_job.user_id, :failed, %{
          import_job_id: import_job.id,
          error: Exception.message(e)
        })
        {:error, e}
    end
  end

  defp broadcast_status(user_id, status, payload) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}#{user_id}", {:sync_status, status, payload})
  end

  @doc """
  Returns the PubSub topic for a user's sync updates.
  """
  def topic(user_id), do: "#{@topic_prefix}#{user_id}"

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
    # Try to find by external_id first (most reliable for Google Contacts)
    # Check all external_ids in the contact's metadata
    with nil <- find_by_any_external_id(user_id, contact),
         nil <- find_by_email(user_id, contact.email),
         nil <- find_by_phone(user_id, contact.phone),
         nil <- find_by_name(user_id, contact.name) do
      nil
    end
  end

  defp find_by_any_external_id(user_id, contact) do
    # Check the primary external_id
    result = if contact.external_id do
      Entities.find_by_external_id(user_id, contact.external_id)
    end

    # Also check all external_ids in metadata
    result || find_by_metadata_external_ids(user_id, contact.metadata[:external_ids])
  end

  defp find_by_metadata_external_ids(_user_id, nil), do: nil
  defp find_by_metadata_external_ids(_user_id, external_ids) when map_size(external_ids) == 0, do: nil
  defp find_by_metadata_external_ids(user_id, external_ids) do
    # Try each external_id until we find a match
    Enum.find_value(external_ids, fn {_source, ext_id} ->
      Entities.find_by_external_id(user_id, ext_id) ||
        Entities.find_by_any_external_id(user_id, ext_id)
    end)
  end

  defp find_by_email(_user_id, nil), do: nil
  defp find_by_email(user_id, email), do: Entities.find_by_email(user_id, email)

  defp find_by_phone(_user_id, nil), do: nil
  defp find_by_phone(user_id, phone), do: Entities.find_by_phone(user_id, phone)

  # Fuzzy name matching as last resort - only for exact matches to avoid false positives
  defp find_by_name(_user_id, nil), do: nil
  defp find_by_name(_user_id, ""), do: nil
  defp find_by_name(user_id, name) do
    Entities.find_by_exact_name(user_id, name)
  end

  defp create_entity(user_id, contact) do
    # Entity schema uses 'description' field - we prioritize organization, fall back to notes
    description = contact.organization || contact.notes

    attrs = %{
      "name" => contact.name,
      "type" => "person",
      "owner_id" => user_id,
      "description" => description,
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
    # Merge metadata - combine external_ids and sources
    existing_metadata = existing.metadata || %{}
    contact_metadata = contact.metadata || %{}

    # Merge external_ids maps
    existing_ext_ids = existing_metadata["external_ids"] || %{}
    contact_ext_ids = contact_metadata[:external_ids] || %{}
    # Also add legacy external_id if present
    contact_ext_ids = if contact.external_id && contact_metadata[:source] do
      Map.put_new(contact_ext_ids, contact_metadata[:source], contact.external_id)
    else
      contact_ext_ids
    end
    merged_ext_ids = Map.merge(existing_ext_ids, stringify_keys(contact_ext_ids))

    # Merge sources lists
    existing_sources = existing_metadata["sources"] || []
    contact_sources = contact_metadata[:sources] || [contact_metadata[:source]]
    merged_sources = (existing_sources ++ contact_sources) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    # Build updates
    updates = %{}

    # Update description if missing
    updates = if is_nil(existing.description) do
      cond do
        contact.organization -> Map.put(updates, "description", contact.organization)
        contact.notes -> Map.put(updates, "description", contact.notes)
        true -> updates
      end
    else
      updates
    end

    # Always update metadata with merged external_ids and sources
    merged_metadata =
      existing_metadata
      |> Map.put("external_ids", merged_ext_ids)
      |> Map.put("sources", merged_sources)

    updates = Map.put(updates, "metadata", merged_metadata)

    Entities.update_entity(existing, updates)

    # Add any new identifiers
    create_identifiers(existing, contact)

    {:ok, :merged}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
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
