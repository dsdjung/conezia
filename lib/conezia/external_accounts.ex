defmodule Conezia.ExternalAccounts do
  @moduledoc """
  The ExternalAccounts context for managing OAuth connections to external services.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.ExternalAccounts.ExternalAccount

  def get_external_account(id), do: Repo.get(ExternalAccount, id)

  def get_external_account!(id), do: Repo.get!(ExternalAccount, id)

  def get_external_account_for_user(id, user_id) do
    ExternalAccount
    |> where([ea], ea.id == ^id and ea.user_id == ^user_id)
    |> Repo.one()
  end

  def list_external_accounts(user_id) do
    ExternalAccount
    |> where([ea], ea.user_id == ^user_id)
    |> order_by([ea], desc: ea.inserted_at)
    |> Repo.all()
  end

  def create_external_account(attrs) do
    %ExternalAccount{}
    |> ExternalAccount.changeset(attrs)
    |> Repo.insert()
  end

  def update_external_account(%ExternalAccount{} = external_account, attrs) do
    external_account
    |> ExternalAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_external_account(%ExternalAccount{} = external_account) do
    Repo.delete(external_account)
  end

  def mark_synced(%ExternalAccount{} = external_account) do
    external_account
    |> ExternalAccount.mark_synced_changeset()
    |> Repo.update()
  end

  def mark_error(%ExternalAccount{} = external_account, error_message) do
    external_account
    |> ExternalAccount.mark_error_changeset(error_message)
    |> Repo.update()
  end

  def trigger_sync(%ExternalAccount{status: "error"} = _external_account) do
    {:error, "Cannot sync account in error state. Please reconnect."}
  end

  def trigger_sync(%ExternalAccount{} = _external_account) do
    # In production, this would queue a background job
    sync_job_id = UUID.uuid4()
    {:ok, sync_job_id}
  end

  @spec exchange_oauth_code(String.t(), String.t(), String.t()) :: {:ok, map(), map()} | {:error, String.t()}
  def exchange_oauth_code(service_name, code, _redirect_uri) do
    # In production, this would exchange the OAuth code for tokens
    case {service_name, code} do
      # Placeholder for future implementation
      {"test_service", "test_success_code"} ->
        account_info = %{email: "test@example.com", name: "Test Account"}
        tokens = %{access_token: "test_token", refresh_token: "test_refresh"}
        {:ok, account_info, tokens}

      _ ->
        {:error, "OAuth exchange not implemented"}
    end
  end
end
