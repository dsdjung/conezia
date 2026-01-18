defmodule ConeziaWeb.OAuthController do
  @moduledoc """
  Controller for handling OAuth authentication flows in the web UI.
  """
  use ConeziaWeb, :controller

  alias Conezia.GoogleOAuth
  alias ConeziaWeb.UserAuth

  @doc """
  GET /auth/google
  Redirects to Google's OAuth authorization page.
  """
  def google(conn, _params) do
    redirect_uri = url(~p"/auth/google/callback")

    # Generate a random state for CSRF protection
    state = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    # Store state in session for verification
    conn = put_session(conn, :oauth_state, state)

    authorize_url = GoogleOAuth.authorize_url(redirect_uri: redirect_uri, state: state)
    redirect(conn, external: authorize_url)
  end

  @doc """
  GET /auth/google/callback
  Handles the OAuth callback from Google.
  """
  def google_callback(conn, %{"code" => code, "state" => state}) do
    stored_state = get_session(conn, :oauth_state)

    # Verify state to prevent CSRF attacks
    if state != stored_state do
      conn
      |> put_flash(:error, "Invalid OAuth state. Please try again.")
      |> redirect(to: ~p"/login")
    else
      redirect_uri = url(~p"/auth/google/callback")

      case GoogleOAuth.callback(code, redirect_uri) do
        {:ok, user, _is_new} ->
          conn
          |> delete_session(:oauth_state)
          |> put_flash(:info, "Welcome! You've signed in with Google.")
          |> UserAuth.log_in_user(user)

        {:error, reason} ->
          conn
          |> delete_session(:oauth_state)
          |> put_flash(:error, "Google sign-in failed: #{reason}")
          |> redirect(to: ~p"/login")
      end
    end
  end

  def google_callback(conn, %{"error" => error}) do
    message =
      case error do
        "access_denied" -> "You cancelled the Google sign-in."
        _ -> "Google sign-in failed: #{error}"
      end

    conn
    |> delete_session(:oauth_state)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login")
  end

  def google_callback(conn, _params) do
    conn
    |> put_flash(:error, "Invalid OAuth callback. Please try again.")
    |> redirect(to: ~p"/login")
  end
end
