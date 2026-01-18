defmodule ConeziaWeb.ExternalAccountController do
  @moduledoc """
  Controller for external account management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.ExternalAccounts
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/external-accounts
  List all external accounts for the current user.
  """
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    accounts = ExternalAccounts.list_external_accounts(user.id)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(accounts, &account_json/1)})
  end

  @doc """
  GET /api/v1/external-accounts/:id
  Get a single external account.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case ExternalAccounts.get_external_account_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("external account", id, conn.request_path))

      account ->
        conn
        |> put_status(:ok)
        |> json(%{data: account_json(account)})
    end
  end

  @doc """
  POST /api/v1/external-accounts
  Connect a new external account.
  """
  def create(conn, %{"service_name" => service_name, "oauth_code" => code, "redirect_uri" => redirect_uri}) do
    user = Guardian.Plug.current_resource(conn)

    case exchange_oauth_code(service_name, code, redirect_uri) do
      {:ok, account_info, tokens} ->
        attrs = %{
          user_id: user.id,
          service_name: service_name,
          account_identifier: account_info.identifier,
          scopes: account_info.scopes,
          access_token_encrypted: encrypt_token(tokens.access_token),
          refresh_token_encrypted: encrypt_token(tokens.refresh_token),
          token_expires_at: tokens.expires_at
        }

        case ExternalAccounts.create_external_account(attrs) do
          {:ok, account} ->
            conn
            |> put_status(:created)
            |> json(%{data: account_json(account)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request("OAuth exchange failed: #{reason}", conn.request_path))
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request(
      "service_name, oauth_code, and redirect_uri are required.",
      conn.request_path
    ))
  end

  @doc """
  DELETE /api/v1/external-accounts/:id
  Disconnect an external account.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case ExternalAccounts.get_external_account_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("external account", id, conn.request_path))

      account ->
        case ExternalAccounts.delete_external_account(account) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "External account disconnected"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/external-accounts/:id/sync
  Trigger a manual sync of an external account.
  """
  def sync(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case ExternalAccounts.get_external_account_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("external account", id, conn.request_path))

      account ->
        case ExternalAccounts.trigger_sync(account) do
          {:ok, sync_job_id} ->
            conn
            |> put_status(:accepted)
            |> json(%{
              data: %{
                sync_job_id: sync_job_id,
                status: "queued"
              }
            })

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/external-accounts/:id/reauth
  Get a new OAuth URL to re-authenticate an account.
  """
  def reauth(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case ExternalAccounts.get_external_account_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("external account", id, conn.request_path))

      account ->
        auth_url = generate_oauth_url(account.service_name, user.id)

        conn
        |> put_status(:ok)
        |> json(%{
          data: %{
            auth_url: auth_url
          }
        })
    end
  end

  # Private helpers

  defp account_json(account) do
    %{
      id: account.id,
      service_name: account.service_name,
      account_identifier: account.account_identifier,
      status: account.status,
      scopes: account.scopes,
      last_synced_at: account.last_synced_at,
      sync_error: account.sync_error,
      inserted_at: account.inserted_at
    }
  end

  defp exchange_oauth_code(service_name, code, _redirect_uri) do
    # TODO: Implement OAuth token exchange for each service
    # This would use Req to call the service's token endpoint
    case {service_name, code} do
      # Placeholder for future implementation/testing
      {"test_service", "test_success_code"} ->
        {:ok, %{identifier: "test@example.com", scopes: ["read"]}, %{access_token: "test", refresh_token: "test_refresh", expires_at: nil}}

      _ ->
        {:error, "OAuth exchange not implemented"}
    end
  end

  defp generate_oauth_url(service_name, _user_id) do
    # TODO: Generate proper OAuth URLs for each service
    case service_name do
      "google_contacts" ->
        "https://accounts.google.com/o/oauth2/v2/auth?scope=contacts.readonly&response_type=code"

      "google_calendar" ->
        "https://accounts.google.com/o/oauth2/v2/auth?scope=calendar.readonly&response_type=code"

      _ ->
        "https://example.com/oauth"
    end
  end

  defp encrypt_token(token) do
    # TODO: Implement proper encryption using a key from config
    # For now, just return the token (NOT FOR PRODUCTION)
    token || ""
  end
end
