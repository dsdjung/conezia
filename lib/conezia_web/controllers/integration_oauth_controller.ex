defmodule ConeziaWeb.IntegrationOAuthController do
  @moduledoc """
  Controller for handling OAuth flows for external service integrations.

  This controller manages the OAuth authorization and callback flow for
  connecting external services like Google Contacts, LinkedIn, etc.
  """
  use ConeziaWeb, :controller

  alias Conezia.Integrations
  alias Conezia.Integrations.ServiceProvider

  @doc """
  GET /integrations/:service/authorize
  Initiates the OAuth flow for the specified service.
  """
  def authorize(conn, %{"service" => service}) do
    user = conn.assigns.current_user

    case ServiceProvider.get_provider(service) do
      {:ok, _provider} ->
        # Generate a random state for CSRF protection
        state = generate_state(user.id, service)

        # Store state in session for verification
        conn = put_session(conn, :integration_oauth_state, state)

        redirect_uri = url(~p"/integrations/#{service}/callback")

        case Integrations.get_authorize_url(service, redirect_uri, state) do
          {:ok, authorize_url} ->
            redirect(conn, external: authorize_url)

          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to start authorization: #{reason}")
            |> redirect(to: ~p"/settings")
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "Unknown service: #{service}")
        |> redirect(to: ~p"/settings")
    end
  end

  @doc """
  GET /integrations/:service/callback
  Handles the OAuth callback from the external service.
  """
  def callback(conn, %{"service" => service, "code" => code, "state" => state}) do
    user = conn.assigns.current_user
    stored_state = get_session(conn, :integration_oauth_state)

    cond do
      is_nil(stored_state) ->
        conn
        |> put_flash(:error, "Session expired. Please try again.")
        |> redirect(to: ~p"/settings")

      not valid_state?(state, stored_state, user.id, service) ->
        conn
        |> delete_session(:integration_oauth_state)
        |> put_flash(:error, "Invalid OAuth state. Please try again.")
        |> redirect(to: ~p"/settings")

      true ->
        redirect_uri = url(~p"/integrations/#{service}/callback")

        case Integrations.handle_oauth_callback(user.id, service, code, redirect_uri) do
          {:ok, _account} ->
            {:ok, provider} = ServiceProvider.get_provider(service)

            conn
            |> delete_session(:integration_oauth_state)
            |> put_flash(:info, "Successfully connected #{provider.display_name()}!")
            |> redirect(to: ~p"/settings")

          {:error, reason} ->
            conn
            |> delete_session(:integration_oauth_state)
            |> put_flash(:error, "Failed to connect: #{reason}")
            |> redirect(to: ~p"/settings")
        end
    end
  end

  def callback(conn, %{"service" => _service, "error" => error}) do
    message =
      case error do
        "access_denied" -> "You cancelled the authorization."
        _ -> "Authorization failed: #{error}"
      end

    conn
    |> delete_session(:integration_oauth_state)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/settings")
  end

  def callback(conn, %{"service" => _service}) do
    conn
    |> put_flash(:error, "Invalid OAuth callback. Please try again.")
    |> redirect(to: ~p"/settings")
  end

  # Private helpers

  defp generate_state(user_id, service) do
    random = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    timestamp = System.system_time(:second)
    data = "#{user_id}:#{service}:#{timestamp}:#{random}"
    signature = :crypto.mac(:hmac, :sha256, state_secret(), data) |> Base.url_encode64(padding: false)
    "#{data}:#{signature}"
  end

  defp valid_state?(provided_state, stored_state, user_id, service) do
    # First check that states match
    if provided_state != stored_state do
      false
    else
      case String.split(provided_state, ":") do
        [state_user_id, state_service, timestamp_str, _random, _signature] ->
          # Verify the state contains correct user and service
          state_user_id == user_id and
            state_service == service and
            state_not_expired?(timestamp_str)

        _ ->
          false
      end
    end
  end

  defp state_not_expired?(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {timestamp, ""} ->
        # State is valid for 10 minutes
        now = System.system_time(:second)
        now - timestamp < 600

      _ ->
        false
    end
  end

  defp state_secret do
    Application.get_env(:conezia, :secret_key_base) ||
      Application.get_env(:conezia, ConeziaWeb.Endpoint)[:secret_key_base] ||
      raise "Secret key base not configured"
  end
end
