defmodule Conezia.Integrations.ServiceProvider do
  @moduledoc """
  Behaviour defining the contract for external service integrations.

  Each service (Google Contacts, LinkedIn, etc.) implements this behaviour
  to provide a consistent interface for OAuth authentication and data fetching.
  """

  @type tokens :: %{
          access_token: String.t(),
          refresh_token: String.t() | nil,
          expires_in: integer() | nil,
          token_type: String.t()
        }

  @type contact :: %{
          name: String.t(),
          email: String.t() | nil,
          phone: String.t() | nil,
          organization: String.t() | nil,
          notes: String.t() | nil,
          external_id: String.t(),
          metadata: map()
        }

  @type fetch_result :: {:ok, [contact()], cursor :: String.t() | nil} | {:error, String.t()}

  @doc "Returns the internal service name (e.g., 'google_contacts')"
  @callback service_name() :: String.t()

  @doc "Returns the human-readable display name (e.g., 'Google Contacts')"
  @callback display_name() :: String.t()

  @doc "Returns the icon class for the service"
  @callback icon() :: String.t()

  @doc "Returns the OAuth scopes required for this service"
  @callback scopes() :: [String.t()]

  @doc "Generates the OAuth authorization URL"
  @callback authorize_url(redirect_uri :: String.t(), state :: String.t()) :: String.t()

  @doc "Exchanges an authorization code for access/refresh tokens"
  @callback exchange_code(code :: String.t(), redirect_uri :: String.t()) ::
              {:ok, tokens()} | {:error, String.t()}

  @doc "Refreshes an expired access token using a refresh token"
  @callback refresh_token(refresh_token :: String.t()) ::
              {:ok, tokens()} | {:error, String.t()}

  @doc "Fetches contacts from the external service"
  @callback fetch_contacts(access_token :: String.t(), opts :: keyword()) :: fetch_result()

  @doc "Revokes access to the service (optional)"
  @callback revoke_access(access_token :: String.t()) :: :ok | {:error, String.t()}

  @optional_callbacks [revoke_access: 1]

  @doc """
  Returns the provider module for a given service name.
  """
  def get_provider("google_contacts"), do: {:ok, Conezia.Integrations.Providers.GoogleContacts}
  def get_provider(service), do: {:error, "Unknown service: #{service}"}

  @doc """
  Returns all available service providers.
  """
  def available_providers do
    [
      %{
        service: "google_contacts",
        module: Conezia.Integrations.Providers.GoogleContacts,
        display_name: "Google Contacts",
        icon: "hero-user-group",
        status: :available
      },
      %{
        service: "linkedin",
        module: nil,
        display_name: "LinkedIn",
        icon: "hero-briefcase",
        status: :coming_soon
      },
      %{
        service: "icloud",
        module: nil,
        display_name: "iCloud",
        icon: "hero-cloud",
        status: :coming_soon
      },
      %{
        service: "outlook",
        module: nil,
        display_name: "Outlook",
        icon: "hero-envelope",
        status: :coming_soon
      }
    ]
  end
end
