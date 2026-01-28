defmodule Conezia.Integrations do
  @moduledoc """
  Context for coordinating external service integrations.

  This module provides the public API for:
  - Initiating OAuth flows for external services
  - Storing and refreshing tokens
  - Triggering sync operations
  - Tracking sync progress
  """

  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.ExternalAccounts
  alias Conezia.ExternalAccounts.ExternalAccount
  alias Conezia.Imports.ImportJob
  alias Conezia.Integrations.ServiceProvider
  alias Conezia.Vault

  @doc """
  Returns all available service providers with their current connection status for a user.
  """
  def list_available_services(user_id) do
    connected_services = list_connected_services(user_id)
    connected_map = Map.new(connected_services, &{&1.service_name, &1})

    ServiceProvider.available_providers()
    |> Enum.map(fn provider ->
      case Map.get(connected_map, provider.service) do
        nil ->
          Map.put(provider, :account, nil)

        account ->
          provider
          |> Map.put(:account, account)
          |> Map.put(:status, :connected)
      end
    end)
  end

  @doc """
  Returns a list of connected external accounts for a user.
  """
  def list_connected_services(user_id) do
    ExternalAccounts.list_external_accounts(user_id)
  end

  @doc """
  Gets a connected account for a specific service.
  """
  def get_connected_account(user_id, service_name) do
    ExternalAccount
    |> where([ea], ea.user_id == ^user_id and ea.service_name == ^service_name)
    |> where([ea], ea.status in ["connected", "pending_reauth"])
    |> Repo.one()
  end

  @doc """
  Generates the OAuth authorization URL for a service.
  """
  def get_authorize_url(service_name, redirect_uri, state) do
    with {:ok, provider} <- ServiceProvider.get_provider(service_name) do
      {:ok, provider.authorize_url(redirect_uri, state)}
    end
  end

  @doc """
  Handles the OAuth callback by exchanging the code for tokens and storing them.
  """
  def handle_oauth_callback(user_id, service_name, code, redirect_uri) do
    with {:ok, provider} <- ServiceProvider.get_provider(service_name),
         {:ok, tokens} <- provider.exchange_code(code, redirect_uri) do
      store_tokens(user_id, service_name, tokens)
    end
  end

  @doc """
  Stores encrypted tokens for a connected service.
  """
  def store_tokens(user_id, service_name, tokens) do
    encrypted_access = Vault.encrypt(tokens.access_token)
    encrypted_refresh = if tokens.refresh_token, do: Vault.encrypt(tokens.refresh_token)

    expires_at =
      if tokens.expires_in do
        DateTime.utc_now() |> DateTime.add(tokens.expires_in, :second)
      end

    account_attrs = %{
      user_id: user_id,
      service_name: service_name,
      account_identifier: get_account_identifier(service_name, tokens.access_token),
      credentials: encrypted_access,
      refresh_token: encrypted_refresh,
      status: "connected",
      token_expires_at: expires_at,
      last_token_refresh_at: DateTime.utc_now(),
      scopes: get_scopes_for_service(service_name)
    }

    case get_connected_account(user_id, service_name) do
      nil ->
        ExternalAccounts.create_external_account(account_attrs)

      existing ->
        ExternalAccounts.update_external_account(existing, account_attrs)
    end
  end

  @doc """
  Refreshes tokens for an external account if needed.
  """
  def refresh_tokens_if_needed(%ExternalAccount{} = account) do
    cond do
      is_nil(account.token_expires_at) ->
        {:ok, account}

      DateTime.compare(account.token_expires_at, DateTime.utc_now()) == :gt ->
        {:ok, account}

      true ->
        refresh_tokens(account)
    end
  end

  @doc """
  Forces a token refresh for an external account.
  """
  def refresh_tokens(%ExternalAccount{} = account) do
    with {:ok, provider} <- ServiceProvider.get_provider(account.service_name),
         {:ok, refresh_token} <- Vault.decrypt(account.refresh_token),
         {:ok, tokens} <- provider.refresh_token(refresh_token) do
      encrypted_access = Vault.encrypt(tokens.access_token)
      encrypted_refresh = if tokens.refresh_token, do: Vault.encrypt(tokens.refresh_token)

      expires_at =
        if tokens.expires_in do
          DateTime.utc_now() |> DateTime.add(tokens.expires_in, :second)
        end

      ExternalAccounts.update_external_account(account, %{
        credentials: encrypted_access,
        refresh_token: encrypted_refresh || account.refresh_token,
        token_expires_at: expires_at,
        last_token_refresh_at: DateTime.utc_now(),
        status: "connected",
        sync_error: nil
      })
    else
      {:error, reason} ->
        ExternalAccounts.mark_error(account, "Token refresh failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Gets the decrypted access token for an account.
  """
  def get_access_token(%ExternalAccount{} = account) do
    Vault.decrypt(account.credentials)
  end

  @doc """
  Gets the decrypted refresh token for an account.
  For iCloud services, this contains the Apple ID.
  """
  def get_refresh_token(%ExternalAccount{} = account) do
    Vault.decrypt(account.refresh_token)
  end

  @doc """
  Triggers a sync for an external account.
  Returns {:ok, import_job} or {:error, reason}.
  """
  def trigger_sync(%ExternalAccount{status: "error"} = _account) do
    {:error, "Cannot sync account in error state. Please reconnect."}
  end

  def trigger_sync(%ExternalAccount{} = account) do
    with {:ok, refreshed_account} <- refresh_tokens_if_needed(account) do
      import_job_attrs = %{
        user_id: refreshed_account.user_id,
        source: refreshed_account.service_name,
        external_account_id: refreshed_account.id,
        status: "pending"
      }

      case Repo.insert(ImportJob.changeset(%ImportJob{}, import_job_attrs)) do
        {:ok, job} ->
          # Queue the actual sync work
          schedule_sync_job(job)
          {:ok, job}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Disconnects an external service by revoking access and deleting the account.
  """
  def disconnect_service(%ExternalAccount{} = account) do
    with {:ok, provider} <- ServiceProvider.get_provider(account.service_name),
         {:ok, access_token} <- get_access_token(account) do
      # Try to revoke access (best effort)
      if function_exported?(provider, :revoke_access, 1) do
        provider.revoke_access(access_token)
      end

      ExternalAccounts.delete_external_account(account)
    else
      {:error, _} ->
        # Even if revocation fails, delete the account
        ExternalAccounts.delete_external_account(account)
    end
  end

  @doc """
  Lists recent import jobs for a user.
  """
  def list_import_jobs(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    ImportJob
    |> where([ij], ij.user_id == ^user_id)
    |> order_by([ij], desc: ij.inserted_at)
    |> limit(^limit)
    |> preload(:external_account)
    |> Repo.all()
  end

  @doc """
  Gets an import job by ID for a user.
  """
  def get_import_job(job_id, user_id) do
    ImportJob
    |> where([ij], ij.id == ^job_id and ij.user_id == ^user_id)
    |> preload(:external_account)
    |> Repo.one()
  end

  # Private helpers

  defp get_account_identifier(service_name, access_token) do
    # For now, generate a unique identifier
    # In production, we'd fetch the user's email/ID from the service
    case service_name do
      "google_contacts" ->
        # Could call Google userinfo API to get email
        "google_#{:crypto.hash(:sha256, access_token) |> Base.encode16(case: :lower) |> binary_part(0, 16)}"

      _ ->
        "#{service_name}_#{:crypto.hash(:sha256, access_token) |> Base.encode16(case: :lower) |> binary_part(0, 16)}"
    end
  end

  defp get_scopes_for_service(service_name) do
    case ServiceProvider.get_provider(service_name) do
      {:ok, provider} -> provider.scopes()
      _ -> []
    end
  end

  defp schedule_sync_job(%ImportJob{} = job) do
    # Queue an Oban job for background processing
    %{import_job_id: job.id}
    |> Conezia.Workers.SyncWorker.new()
    |> Oban.insert()
  end
end
