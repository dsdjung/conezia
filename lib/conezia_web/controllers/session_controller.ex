defmodule ConeziaWeb.SessionController do
  @moduledoc """
  Handles user session management for the web UI.
  """
  use ConeziaWeb, :controller

  alias Conezia.Accounts
  alias ConeziaWeb.UserAuth

  @doc """
  Creates a new session (login).
  """
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.authenticate_by_email_password(email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, user_params)

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/login")
    end
  end

  @doc """
  Deletes the session (logout).
  """
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
