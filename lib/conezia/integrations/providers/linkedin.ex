defmodule Conezia.Integrations.Providers.LinkedIn do
  @moduledoc """
  LinkedIn integration using the LinkedIn API.

  This module implements the ServiceProvider behaviour to fetch connections
  from a user's LinkedIn account.

  Note: LinkedIn's API for fetching connections is limited. The Connections API
  requires partner-level access. For most applications, we can only access
  the authenticated user's basic profile and email.

  For full connections access, you need to apply for the LinkedIn Marketing Developer
  Platform or use LinkedIn's Connection Export feature manually.
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @linkedin_auth_url "https://www.linkedin.com/oauth/v2/authorization"
  @linkedin_token_url "https://www.linkedin.com/oauth/v2/accessToken"
  @linkedin_api "https://api.linkedin.com/v2"

  @impl true
  def service_name, do: "linkedin"

  @impl true
  def display_name, do: "LinkedIn"

  @impl true
  def icon, do: "hero-briefcase"

  @impl true
  def scopes do
    # Basic scopes available to all apps
    # r_liteprofile: Basic profile (name, photo)
    # r_emailaddress: Primary email address
    # Note: r_network (connections) requires partner access
    ["r_liteprofile", "r_emailaddress"]
  end

  @impl true
  def authorize_url(redirect_uri, state) do
    params = %{
      response_type: "code",
      client_id: client_id(),
      redirect_uri: redirect_uri,
      state: state,
      scope: Enum.join(scopes(), " ")
    }

    "#{@linkedin_auth_url}?#{URI.encode_query(params)}"
  end

  @impl true
  def exchange_code(code, redirect_uri) do
    body = %{
      grant_type: "authorization_code",
      code: code,
      client_id: client_id(),
      client_secret: client_secret(),
      redirect_uri: redirect_uri
    }

    case Req.post(@linkedin_token_url, form: body) do
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
        {:error, "Failed to connect to LinkedIn: #{inspect(reason)}"}
    end
  end

  @impl true
  def refresh_token(refresh_token) do
    body = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: client_id(),
      client_secret: client_secret()
    }

    case Req.post(@linkedin_token_url, form: body) do
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
        {:error, "Failed to connect to LinkedIn: #{inspect(reason)}"}
    end
  end

  @impl true
  def fetch_contacts(access_token, opts \\ []) do
    # LinkedIn's Connections API (r_network) requires partner-level access
    # For standard apps, we can only fetch the user's own profile
    # This serves as a proof of connection and can be expanded with partner access

    _page_token = Keyword.get(opts, :page_token)

    # Try to fetch connections if we have partner access
    case fetch_connections(access_token) do
      {:ok, connections} ->
        {:ok, connections, nil}

      {:error, "Access denied" <> _} ->
        # Fall back to fetching just the user's profile as a test connection
        case fetch_own_profile(access_token) do
          {:ok, profile} ->
            {:ok, [profile], nil}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def revoke_access(_access_token) do
    # LinkedIn doesn't have a token revocation endpoint
    # Users need to revoke access from their LinkedIn settings
    :ok
  end

  # Private helpers

  defp fetch_connections(access_token) do
    # This endpoint requires r_network scope (partner access only)
    url = "#{@linkedin_api}/connections?q=viewer&start=0&count=50"
    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"X-Restli-Protocol-Version", "2.0.0"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        connections = parse_connections(body["elements"] || [])
        {:ok, connections}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied - connections API requires partner access"}

      {:ok, %{status: status, body: body}} ->
        error = body["message"] || "Unknown error"
        {:error, "Failed to fetch connections (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to LinkedIn: #{inspect(reason)}"}
    end
  end

  defp fetch_own_profile(access_token) do
    # Fetch basic profile using v2 API
    profile_url = "#{@linkedin_api}/me?projection=(id,firstName,lastName,profilePicture(displayImage~:playableStreams))"
    email_url = "#{@linkedin_api}/emailAddress?q=members&projection=(elements*(handle~))"

    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"X-Restli-Protocol-Version", "2.0.0"}
    ]

    with {:ok, %{status: 200, body: profile_body}} <- Req.get(profile_url, headers: headers),
         {:ok, %{status: 200, body: email_body}} <- Req.get(email_url, headers: headers) do
      contact = parse_profile(profile_body, email_body)
      {:ok, contact}
    else
      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: status, body: body}} ->
        error = body["message"] || "Unknown error"
        {:error, "Failed to fetch profile (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to LinkedIn: #{inspect(reason)}"}
    end
  end

  defp parse_connections(elements) do
    Enum.map(elements, &parse_connection_element/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_connection_element(element) do
    # Connection element structure varies based on API version
    first_name = get_in(element, ["firstName", "localized", "en_US"]) ||
                 get_in(element, ["firstName"])
    last_name = get_in(element, ["lastName", "localized", "en_US"]) ||
                get_in(element, ["lastName"])

    name = [first_name, last_name]
           |> Enum.reject(&is_nil/1)
           |> Enum.join(" ")

    if name != "" do
      %{
        name: name,
        email: nil,
        phone: nil,
        organization: get_in(element, ["positions", "values", Access.at(0), "company", "name"]),
        notes: nil,
        external_id: "linkedin:#{element["id"]}",
        metadata: %{
          photo_url: get_profile_picture(element),
          source: "linkedin"
        }
      }
    end
  end

  defp parse_profile(profile_body, email_body) do
    first_name = get_localized_name(profile_body["firstName"])
    last_name = get_localized_name(profile_body["lastName"])

    name = [first_name, last_name]
           |> Enum.reject(&is_nil/1)
           |> Enum.join(" ")

    email = get_email_from_response(email_body)

    %{
      name: name,
      email: email,
      phone: nil,
      organization: nil,
      notes: "Connected via LinkedIn",
      external_id: "linkedin:#{profile_body["id"]}",
      metadata: %{
        photo_url: get_profile_picture_v2(profile_body),
        source: "linkedin"
      }
    }
  end

  defp get_localized_name(nil), do: nil
  defp get_localized_name(%{"localized" => localized}) do
    # Get the first available localization
    localized
    |> Map.values()
    |> List.first()
  end
  defp get_localized_name(name) when is_binary(name), do: name
  defp get_localized_name(_), do: nil

  defp get_email_from_response(nil), do: nil
  defp get_email_from_response(%{"elements" => elements}) when is_list(elements) do
    elements
    |> Enum.find_value(fn element ->
      get_in(element, ["handle~", "emailAddress"])
    end)
  end
  defp get_email_from_response(_), do: nil

  defp get_profile_picture(element) do
    get_in(element, ["profilePicture", "displayImage"])
  end

  defp get_profile_picture_v2(profile) do
    # v2 API has a complex structure for profile pictures
    display_image = get_in(profile, ["profilePicture", "displayImage~", "elements"])

    case display_image do
      [_ | _] = elements ->
        # Get the largest image
        elements
        |> Enum.max_by(fn el -> get_in(el, ["data", "com.linkedin.digitalmedia.mediaartifact.StillImage", "storageSize", "width"]) || 0 end, fn -> nil end)
        |> case do
          nil -> nil
          el -> get_in(el, ["identifiers", Access.at(0), "identifier"])
        end

      _ ->
        nil
    end
  end

  defp client_id do
    config()[:client_id] || raise "LinkedIn OAuth client_id not configured"
  end

  defp client_secret do
    config()[:client_secret] || raise "LinkedIn OAuth client_secret not configured"
  end

  defp config do
    Application.get_env(:conezia, :linkedin_oauth, [])
  end
end
