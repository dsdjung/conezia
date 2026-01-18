defmodule Conezia.Integrations.Providers.GoogleContacts do
  @moduledoc """
  Google Contacts integration using the Google People API.

  This module implements the ServiceProvider behaviour to fetch contacts
  from a user's Google account.
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_people_api "https://people.googleapis.com/v1"

  @impl true
  def service_name, do: "google_contacts"

  @impl true
  def display_name, do: "Google Contacts"

  @impl true
  def icon, do: "hero-user-group"

  @impl true
  def scopes do
    ["https://www.googleapis.com/auth/contacts.readonly"]
  end

  @impl true
  def authorize_url(redirect_uri, state) do
    params = %{
      client_id: client_id(),
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: Enum.join(scopes(), " "),
      access_type: "offline",
      prompt: "consent",
      state: state
    }

    "#{@google_auth_url}?#{URI.encode_query(params)}"
  end

  @impl true
  def exchange_code(code, redirect_uri) do
    body = %{
      code: code,
      client_id: client_id(),
      client_secret: client_secret(),
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    }

    case Req.post(@google_token_url, form: body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"],
           expires_in: body["expires_in"],
           token_type: body["token_type"] || "Bearer"
         }}

      {:ok, %{status: status, body: body}} ->
        error = body["error_description"] || body["error"] || "Unknown error"
        {:error, "Token exchange failed (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @impl true
  def refresh_token(refresh_token) do
    body = %{
      refresh_token: refresh_token,
      client_id: client_id(),
      client_secret: client_secret(),
      grant_type: "refresh_token"
    }

    case Req.post(@google_token_url, form: body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"] || refresh_token,
           expires_in: body["expires_in"],
           token_type: body["token_type"] || "Bearer"
         }}

      {:ok, %{status: status, body: body}} ->
        error = body["error_description"] || body["error"] || "Unknown error"
        {:error, "Token refresh failed (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @impl true
  def fetch_contacts(access_token, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 100)
    page_token = Keyword.get(opts, :page_token)

    params = %{
      personFields: "names,emailAddresses,phoneNumbers,organizations,biographies,photos",
      pageSize: page_size
    }

    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@google_people_api}/people/me/connections?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        contacts = parse_connections(body["connections"] || [])
        next_page_token = body["nextPageToken"]
        {:ok, contacts, next_page_token}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied - check scopes"}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch contacts (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @impl true
  def revoke_access(access_token) do
    url = "https://oauth2.googleapis.com/revoke?token=#{access_token}"

    case Req.post(url, headers: [{"content-type", "application/x-www-form-urlencoded"}]) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: _status}} -> :ok
      {:error, reason} -> {:error, "Failed to revoke: #{inspect(reason)}"}
    end
  end

  # Private helpers

  defp parse_connections(connections) do
    Enum.map(connections, &parse_connection/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_connection(connection) do
    name = get_primary_name(connection["names"])

    # Skip contacts without names
    if name do
      %{
        name: name,
        email: get_primary_email(connection["emailAddresses"]),
        phone: get_primary_phone(connection["phoneNumbers"]),
        organization: get_primary_organization(connection["organizations"]),
        notes: get_biography(connection["biographies"]),
        external_id: connection["resourceName"],
        metadata: %{
          photo_url: get_photo_url(connection["photos"]),
          source: "google_contacts"
        }
      }
    end
  end

  defp get_primary_name(nil), do: nil

  defp get_primary_name(names) do
    primary = Enum.find(names, List.first(names), &(&1["metadata"]["primary"] == true))
    primary && primary["displayName"]
  end

  defp get_primary_email(nil), do: nil

  defp get_primary_email(emails) do
    primary = Enum.find(emails, List.first(emails), &(&1["metadata"]["primary"] == true))
    primary && primary["value"]
  end

  defp get_primary_phone(nil), do: nil

  defp get_primary_phone(phones) do
    primary = Enum.find(phones, List.first(phones), &(&1["metadata"]["primary"] == true))
    primary && primary["value"]
  end

  defp get_primary_organization(nil), do: nil

  defp get_primary_organization(orgs) do
    primary = Enum.find(orgs, List.first(orgs), &(&1["metadata"]["primary"] == true))
    primary && primary["name"]
  end

  defp get_biography(nil), do: nil
  defp get_biography([]), do: nil
  defp get_biography([bio | _]), do: bio["value"]

  defp get_photo_url(nil), do: nil
  defp get_photo_url([]), do: nil
  defp get_photo_url([photo | _]), do: photo["url"]

  defp client_id do
    config()[:client_id] || raise "Google OAuth client_id not configured"
  end

  defp client_secret do
    config()[:client_secret] || raise "Google OAuth client_secret not configured"
  end

  defp config do
    Application.get_env(:conezia, :google_oauth, [])
  end
end
