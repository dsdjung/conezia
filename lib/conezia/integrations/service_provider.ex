defmodule Conezia.Integrations.ServiceProvider do
  @moduledoc """
  Behaviour defining the contract for external service integrations.

  Each service (Google, LinkedIn, etc.) implements this behaviour
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

  @doc "Returns the internal service name (e.g., 'google')"
  @callback service_name() :: String.t()

  @doc "Returns the human-readable display name (e.g., 'Google')"
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
  def get_provider("google"), do: {:ok, Conezia.Integrations.Providers.Google}
  def get_provider("linkedin"), do: {:ok, Conezia.Integrations.Providers.LinkedIn}
  def get_provider("icloud"), do: {:ok, Conezia.Integrations.Providers.ICloudContacts}
  def get_provider("facebook"), do: {:ok, Conezia.Integrations.Providers.Facebook}
  def get_provider(service), do: {:error, "Unknown service: #{service}"}

  @doc """
  Returns all available service providers.
  """
  def available_providers do
    [
      %{
        service: "google",
        module: Conezia.Integrations.Providers.Google,
        display_name: "Google",
        description: "Import contacts from Google Contacts, Calendar, and Gmail",
        icon: "hero-cloud",
        status: google_status()
      },
      %{
        service: "linkedin",
        module: Conezia.Integrations.Providers.LinkedIn,
        display_name: "LinkedIn",
        description: "Import your LinkedIn profile",
        icon: "hero-briefcase",
        status: linkedin_status()
      },
      %{
        service: "icloud",
        module: Conezia.Integrations.Providers.ICloudContacts,
        display_name: "iCloud Contacts",
        description: "Import contacts from iCloud",
        icon: "hero-cloud",
        status: :available
      },
      %{
        service: "facebook",
        module: Conezia.Integrations.Providers.Facebook,
        display_name: "Facebook",
        description: "Import friends from Facebook",
        icon: "hero-user-group",
        status: facebook_status()
      },
      %{
        service: "outlook",
        module: nil,
        display_name: "Outlook",
        description: "Import contacts from Outlook",
        icon: "hero-envelope",
        status: :coming_soon
      }
    ]
  end

  # Google services are available if configured
  defp google_status do
    config = Application.get_env(:conezia, :google_oauth, [])
    if config[:client_id] && config[:client_secret] do
      :available
    else
      :coming_soon
    end
  end

  # LinkedIn is available if configured, otherwise coming_soon
  defp linkedin_status do
    config = Application.get_env(:conezia, :linkedin_oauth, [])
    if config[:client_id] && config[:client_secret] do
      :available
    else
      :coming_soon
    end
  end

  # Facebook is available if configured
  defp facebook_status do
    config = Application.get_env(:conezia, :facebook_oauth, [])
    if config[:client_id] && config[:client_secret] do
      :available
    else
      :coming_soon
    end
  end
end
