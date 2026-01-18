defmodule ConeziaWeb.AuthErrorHandler do
  @moduledoc """
  Error handler for Guardian authentication errors.
  """
  import Plug.Conn
  import Phoenix.Controller

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, _reason}, _opts) do
    {status, message} =
      case type do
        :unauthenticated ->
          {401, "Authentication required. Please provide a valid bearer token."}

        :invalid_token ->
          {401, "Invalid or expired token."}

        :no_resource_found ->
          {401, "User not found for the provided token."}

        :token_expired ->
          {401, "Token has expired. Please refresh your token."}

        _ ->
          {401, "Authentication failed."}
      end

    conn
    |> put_status(status)
    |> put_resp_content_type("application/json")
    |> json(%{
      error: %{
        type: "https://api.conezia.com/errors/unauthorized",
        title: "Unauthorized",
        status: status,
        detail: message
      }
    })
    |> halt()
  end
end
