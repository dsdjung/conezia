defmodule Conezia.Integrations.Providers.ICloudContacts do
  @moduledoc """
  iCloud Contacts integration using Apple's CloudKit and CardDAV protocols.

  Note: Apple does not provide a standard OAuth flow for iCloud. This integration
  uses app-specific passwords for authentication via CardDAV. Users need to:
  1. Enable two-factor authentication on their Apple ID
  2. Generate an app-specific password at appleid.apple.com
  3. Use their Apple ID email and the app-specific password to connect

  This is the standard approach used by third-party apps to access iCloud data.
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @carddav_url "https://contacts.icloud.com"
  @principal_path "/:principals:/"
  @addressbook_home_path "/:addressbook-home:/"

  @impl true
  def service_name, do: "icloud"

  @impl true
  def display_name, do: "iCloud Contacts"

  @impl true
  def icon, do: "hero-cloud"

  @impl true
  def scopes do
    # iCloud uses app-specific passwords, not OAuth scopes
    ["contacts"]
  end

  @impl true
  def authorize_url(_redirect_uri, _state) do
    # iCloud doesn't use standard OAuth
    # Return a special URL that our frontend will handle differently
    # to show a username/password form instead of redirecting
    "icloud://auth"
  end

  @impl true
  def exchange_code(credentials_json, _redirect_uri) do
    # For iCloud, the "code" is actually a JSON string containing credentials
    # Format: {"apple_id": "user@icloud.com", "app_password": "xxxx-xxxx-xxxx-xxxx"}
    case Jason.decode(credentials_json) do
      {:ok, %{"apple_id" => apple_id, "app_password" => app_password}} ->
        # Verify the credentials work by making a test request
        case verify_credentials(apple_id, app_password) do
          :ok ->
            # For iCloud, we store credentials as "tokens"
            # The app_password is the access_token (used for all requests)
            # apple_id goes in metadata
            {:ok,
             %{
               access_token: app_password,
               refresh_token: apple_id,
               expires_in: nil,
               token_type: "Basic"
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, _} ->
        {:error, "Invalid credentials format - expected apple_id and app_password"}

      {:error, _} ->
        {:error, "Invalid credentials format - expected JSON"}
    end
  end

  @impl true
  def refresh_token(_apple_id) do
    # iCloud app-specific passwords don't expire or refresh
    # Return the same credentials
    # Note: apple_id is stored in refresh_token field
    {:error, "iCloud uses app-specific passwords which don't need refreshing. Please reconnect if access is revoked."}
  end

  @impl true
  def fetch_contacts(app_password, opts \\ []) do
    apple_id = Keyword.get(opts, :apple_id) || Keyword.get(opts, :refresh_token)

    unless apple_id do
      {:error, "Apple ID required for iCloud requests"}
    else
      fetch_carddav_contacts(apple_id, app_password)
    end
  end

  @impl true
  def revoke_access(_access_token) do
    # App-specific passwords are managed through appleid.apple.com
    # We can't revoke them programmatically
    :ok
  end

  # Private helpers

  defp verify_credentials(apple_id, app_password) do
    auth = Base.encode64("#{apple_id}:#{app_password}")
    headers = [
      {"authorization", "Basic #{auth}"},
      {"content-type", "application/xml; charset=utf-8"}
    ]

    # Try to fetch the principal to verify credentials
    propfind_body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:current-user-principal/>
      </d:prop>
    </d:propfind>
    """

    case Req.request(
           method: :propfind,
           url: "#{@carddav_url}#{@principal_path}",
           headers: headers,
           body: propfind_body
         ) do
      {:ok, %{status: status}} when status in [200, 207] ->
        :ok

      {:ok, %{status: 401}} ->
        {:error, "Invalid Apple ID or app-specific password"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied - ensure two-factor authentication is enabled"}

      {:ok, %{status: status, body: body}} ->
        {:error, "iCloud verification failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
    end
  end

  defp fetch_carddav_contacts(apple_id, app_password) do
    auth = Base.encode64("#{apple_id}:#{app_password}")
    headers = [
      {"authorization", "Basic #{auth}"},
      {"content-type", "application/xml; charset=utf-8"},
      {"depth", "1"}
    ]

    # First, get the addressbook home set
    case get_addressbook_home(headers) do
      {:ok, addressbook_path} ->
        # Then fetch all vcards from the default addressbook
        fetch_vcards(addressbook_path, headers)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_addressbook_home(headers) do
    propfind_body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:prop>
        <card:addressbook-home-set/>
      </d:prop>
    </d:propfind>
    """

    case Req.request(
           method: :propfind,
           url: "#{@carddav_url}#{@principal_path}",
           headers: headers,
           body: propfind_body
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 207] ->
        # Parse the XML response to get the addressbook home path
        case parse_addressbook_home(body) do
          nil -> {:ok, @addressbook_home_path}
          path -> {:ok, path}
        end

      {:ok, %{status: status}} ->
        {:error, "Failed to get addressbook home (#{status})"}

      {:error, reason} ->
        {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
    end
  end

  defp parse_addressbook_home(xml_body) when is_binary(xml_body) do
    # Simple regex extraction - for production, use proper XML parsing
    case Regex.run(~r/<d:href>([^<]+)<\/d:href>/i, xml_body) do
      [_, href] -> href
      _ -> nil
    end
  end

  defp parse_addressbook_home(_), do: nil

  defp fetch_vcards(addressbook_path, headers) do
    # Request all vcards with a REPORT request
    report_body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:prop>
        <d:getetag/>
        <card:address-data/>
      </d:prop>
    </card:addressbook-query>
    """

    url = "#{@carddav_url}#{addressbook_path}card/"

    case Req.request(
           method: :report,
           url: url,
           headers: headers ++ [{"depth", "1"}],
           body: report_body
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 207] ->
        contacts = parse_vcards_response(body)
        # CardDAV doesn't have pagination like REST APIs
        {:ok, contacts, nil}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied - check permissions"}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to fetch contacts (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
    end
  end

  defp parse_vcards_response(body) when is_binary(body) do
    # Extract vCard data from the XML response
    # Pattern: <card:address-data>...vCard content...</card:address-data>
    ~r/<card:address-data[^>]*>([\s\S]*?)<\/card:address-data>/i
    |> Regex.scan(body)
    |> Enum.map(fn [_, vcard] -> parse_vcard(vcard) end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_vcards_response(_), do: []

  defp parse_vcard(vcard_text) do
    # Parse vCard format (simplified parser)
    lines = String.split(vcard_text, ~r/\r?\n/)

    name = extract_vcard_field(lines, "FN")
    email = extract_vcard_field(lines, "EMAIL")
    phone = extract_vcard_field(lines, "TEL")
    org = extract_vcard_field(lines, "ORG")
    note = extract_vcard_field(lines, "NOTE")
    uid = extract_vcard_field(lines, "UID")

    if name do
      %{
        name: name,
        email: email,
        phone: phone,
        organization: org,
        notes: note,
        external_id: uid || "icloud:#{:crypto.hash(:sha256, vcard_text) |> Base.encode16(case: :lower) |> binary_part(0, 16)}",
        metadata: %{
          source: "icloud"
        }
      }
    end
  end

  defp extract_vcard_field(lines, field_name) do
    # vCard fields can have parameters like EMAIL;TYPE=HOME:user@example.com
    pattern = ~r/^#{field_name}(?:;[^:]+)?:(.+)$/i

    Enum.find_value(lines, fn line ->
      case Regex.run(pattern, String.trim(line)) do
        [_, value] -> String.trim(value)
        _ -> nil
      end
    end)
  end
end
