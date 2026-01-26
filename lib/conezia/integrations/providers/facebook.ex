defmodule Conezia.Integrations.Providers.Facebook do
  @moduledoc """
  Facebook integration using the Facebook Graph API.

  This module implements the ServiceProvider behaviour to fetch friends
  from a user's Facebook account.

  Note: Facebook's API has significant limitations:
  - Only friends who also use the same app can be retrieved
  - Full friends list access requires app review and approval
  - Many fields require additional permissions

  For most use cases, this will import a limited subset of friends
  who have also authorized this app.
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @facebook_auth_url "https://www.facebook.com/v19.0/dialog/oauth"
  @facebook_token_url "https://graph.facebook.com/v19.0/oauth/access_token"
  @facebook_graph_api "https://graph.facebook.com/v19.0"

  @impl true
  def service_name, do: "facebook"

  @impl true
  def display_name, do: "Facebook"

  @impl true
  def icon, do: "hero-user-group"

  @impl true
  def scopes do
    # user_friends: Get list of friends who use this app
    # public_profile: Basic profile info
    # email: User's email (for deduplication)
    ["public_profile", "email", "user_friends"]
  end

  @impl true
  def authorize_url(redirect_uri, state) do
    params = %{
      client_id: client_id(),
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: Enum.join(scopes(), ","),
      state: state
    }

    "#{@facebook_auth_url}?#{URI.encode_query(params)}"
  end

  @impl true
  def exchange_code(code, redirect_uri) do
    params = %{
      code: code,
      client_id: client_id(),
      client_secret: client_secret(),
      redirect_uri: redirect_uri
    }

    url = "#{@facebook_token_url}?#{URI.encode_query(params)}"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["access_token"],
           # Facebook doesn't provide refresh tokens by default
           # Long-lived tokens last ~60 days
           refresh_token: nil,
           expires_in: body["expires_in"],
           token_type: body["token_type"] || "Bearer"
         }}

      {:ok, %{status: _status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Token exchange failed: #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Facebook: #{inspect(reason)}"}
    end
  end

  @impl true
  def refresh_token(access_token) do
    # Facebook uses token exchange for long-lived tokens
    # Exchange short-lived token for long-lived token
    params = %{
      grant_type: "fb_exchange_token",
      client_id: client_id(),
      client_secret: client_secret(),
      fb_exchange_token: access_token
    }

    url = "#{@facebook_token_url}?#{URI.encode_query(params)}"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: nil,
           expires_in: body["expires_in"],
           token_type: body["token_type"] || "Bearer"
         }}

      {:ok, %{status: _status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Token refresh failed: #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Facebook: #{inspect(reason)}"}
    end
  end

  @impl true
  def fetch_contacts(access_token, opts \\ []) do
    after_cursor = Keyword.get(opts, :page_token)
    limit = Keyword.get(opts, :page_size, 100)

    # First fetch friends who also use this app
    friends_result = fetch_friends(access_token, after_cursor, limit)

    case friends_result do
      {:ok, friends, next_cursor} ->
        # Also fetch the user's own profile for reference
        contacts = friends
        {:ok, contacts, next_cursor}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def revoke_access(access_token) do
    url = "#{@facebook_graph_api}/me/permissions"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.delete(url, headers: headers) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: _status}} -> :ok
      {:error, reason} -> {:error, "Failed to revoke: #{inspect(reason)}"}
    end
  end

  # Private helpers

  defp fetch_friends(access_token, after_cursor, limit) do
    params = %{
      fields: "id,name,picture.type(large),email",
      limit: limit
    }

    params = if after_cursor, do: Map.put(params, :after, after_cursor), else: params

    url = "#{@facebook_graph_api}/me/friends?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        friends = parse_friends(body["data"] || [])
        next_cursor = get_in(body, ["paging", "cursors", "after"])
        {:ok, friends, next_cursor}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Access denied"
        {:error, "Access denied: #{error}"}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch friends (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Facebook: #{inspect(reason)}"}
    end
  end

  defp parse_friends(friends) do
    Enum.map(friends, &parse_friend/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_friend(friend) do
    name = friend["name"]

    if name do
      %{
        name: name,
        email: friend["email"],
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: "fb:#{friend["id"]}",
        metadata: %{
          source: "facebook",
          facebook_id: friend["id"],
          profile_picture: get_in(friend, ["picture", "data", "url"])
        }
      }
    end
  end

  defp client_id do
    config()[:client_id] || raise "Facebook OAuth client_id not configured"
  end

  defp client_secret do
    config()[:client_secret] || raise "Facebook OAuth client_secret not configured"
  end

  defp config do
    Application.get_env(:conezia, :facebook_oauth, [])
  end
end
