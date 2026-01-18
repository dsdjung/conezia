defmodule Conezia.GoogleOAuth do
  @moduledoc """
  Google OAuth 2.0 integration for authentication.

  Handles the OAuth flow:
  1. Generate authorization URL
  2. Exchange authorization code for tokens
  3. Fetch user info from Google
  4. Create or find user in the database
  """

  alias Conezia.Accounts

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_userinfo_url "https://www.googleapis.com/oauth2/v2/userinfo"

  @doc """
  Generates the Google OAuth authorization URL.

  ## Options
    * `:redirect_uri` - The callback URL (required)
    * `:state` - Optional state parameter for CSRF protection
  """
  def authorize_url(opts \\ []) do
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)
    state = Keyword.get(opts, :state)

    params = %{
      client_id: client_id(),
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: "openid email profile",
      access_type: "offline",
      prompt: "select_account"
    }

    params = if state, do: Map.put(params, :state, state), else: params

    "#{@google_auth_url}?#{URI.encode_query(params)}"
  end

  @doc """
  Exchanges an authorization code for tokens and fetches user info.

  Returns `{:ok, user, is_new}` on success, where `is_new` indicates
  if this is a newly created user.
  """
  def callback(code, redirect_uri) do
    with {:ok, tokens} <- exchange_code(code, redirect_uri),
         {:ok, google_user} <- fetch_user_info(tokens.access_token),
         {:ok, user, is_new} <- find_or_create_user(google_user) do
      {:ok, user, is_new}
    end
  end

  @doc """
  Exchanges an authorization code for access and refresh tokens.
  """
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
        {:ok, %{
          access_token: body["access_token"],
          refresh_token: body["refresh_token"],
          expires_in: body["expires_in"],
          token_type: body["token_type"]
        }}

      {:ok, %{status: status, body: body}} ->
        error = body["error_description"] || body["error"] || "Unknown error"
        {:error, "Google token exchange failed (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @doc """
  Fetches user information from Google using an access token.
  """
  def fetch_user_info(access_token) do
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(@google_userinfo_url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{
          id: body["id"],
          email: body["email"],
          name: body["name"],
          picture: body["picture"],
          verified_email: body["verified_email"]
        }}

      {:ok, %{status: status, body: body}} ->
        error = body["error"]["message"] || "Unknown error"
        {:error, "Failed to fetch user info (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @doc """
  Finds an existing user by Google ID or creates a new one.
  """
  def find_or_create_user(google_user) do
    user_attrs = %{
      email: google_user.email,
      name: google_user.name,
      avatar_url: google_user.picture
    }

    case Accounts.get_or_create_user_from_oauth("google", google_user.id, user_attrs) do
      {:ok, user} ->
        # Check if this was a newly created user by checking if they have any entities
        is_new = is_nil(user.onboarding_completed_at)
        {:ok, user, is_new}

      {:error, changeset} ->
        {:error, "Failed to create user: #{inspect(changeset.errors)}"}
    end
  end

  # Private helpers

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
