defmodule ConeziaWeb.Plugs.Auth do
  @moduledoc """
  Authentication plugs for the Conezia API.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Conezia.Guardian

  @doc """
  Plug that ensures the request has a valid authentication token.
  """
  def require_auth(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: %{
            type: "https://api.conezia.com/errors/unauthorized",
            title: "Unauthorized",
            status: 401,
            detail: "Authentication required. Please provide a valid bearer token."
          }
        })
        |> halt()

      _user ->
        conn
    end
  end

  @doc """
  Plug that optionally loads the current user from the token.
  Does not halt the request if no token is present.
  """
  def load_current_user(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            assign(conn, :current_user, user)

          {:error, _reason} ->
            conn
        end

      _ ->
        conn
    end
  end

  @doc """
  Plug that ensures the current user has verified their email.
  """
  def require_verified_email(conn, _opts) do
    case conn.assigns[:current_user] do
      %{email_verified_at: nil} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: %{
            type: "https://api.conezia.com/errors/forbidden",
            title: "Forbidden",
            status: 403,
            detail: "Email verification required. Please verify your email address."
          }
        })
        |> halt()

      _ ->
        conn
    end
  end

  @doc """
  Helper function to get the current user from the connection.
  """
  def current_user(conn) do
    Guardian.Plug.current_resource(conn)
  end
end
