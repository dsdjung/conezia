defmodule Conezia.Integrations.Providers.GoogleCalendar do
  @moduledoc """
  Google Calendar integration using the Google Calendar API.

  This module implements the ServiceProvider behaviour to fetch calendar events
  and identify contacts the user interacts with frequently through meetings.
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_calendar_api "https://www.googleapis.com/calendar/v3"

  @impl true
  def service_name, do: "google_calendar"

  @impl true
  def display_name, do: "Google Calendar"

  @impl true
  def icon, do: "hero-calendar-days"

  @impl true
  def scopes do
    ["https://www.googleapis.com/auth/calendar.readonly"]
  end

  @impl true
  def authorize_url(redirect_uri, state) do
    params = %{
      client_id: client_id(),
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: Enum.join(scopes(), " "),
      access_type: "offline",
      prompt: "consent",
      state: state
    }

    "#{@google_auth_url}?#{URI.encode_query(params)}"
  end

  @impl true
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
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @impl true
  def refresh_token(refresh_token) do
    body = %{
      refresh_token: refresh_token,
      client_id: client_id(),
      client_secret: client_secret(),
      grant_type: "refresh_token"
    }

    case Req.post(@google_token_url, form: body) do
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
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @impl true
  def fetch_contacts(access_token, opts \\ []) do
    page_token = Keyword.get(opts, :page_token)
    max_results = Keyword.get(opts, :page_size, 250)

    # Fetch events from the past 90 days to identify frequent contacts
    time_min =
      DateTime.utc_now()
      |> DateTime.add(-90, :day)
      |> DateTime.to_iso8601()

    time_max = DateTime.utc_now() |> DateTime.to_iso8601()

    params = %{
      timeMin: time_min,
      timeMax: time_max,
      maxResults: max_results,
      singleEvents: true,
      orderBy: "startTime"
    }

    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@google_calendar_api}/calendars/primary/events?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        contacts = extract_contacts_from_events(body["items"] || [])
        next_page_token = body["nextPageToken"]
        {:ok, contacts, next_page_token}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied - check scopes"}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch calendar events (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  @impl true
  def revoke_access(access_token) do
    url = "https://oauth2.googleapis.com/revoke?token=#{access_token}"

    case Req.post(url, headers: [{"content-type", "application/x-www-form-urlencoded"}]) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: _status}} -> :ok
      {:error, reason} -> {:error, "Failed to revoke: #{inspect(reason)}"}
    end
  end

  # Private helpers

  defp extract_contacts_from_events(events) do
    events
    |> Enum.flat_map(&extract_attendees/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.email)
  end

  defp extract_attendees(event) do
    attendees = event["attendees"] || []
    organizer = event["organizer"]

    # Extract attendees
    attendee_contacts =
      Enum.map(attendees, fn attendee ->
        # Skip self (the authenticated user) and resource calendars
        if attendee["self"] != true && !is_resource_calendar?(attendee["email"]) do
          parse_attendee(attendee, event)
        end
      end)

    # Also include organizer if they're not self
    organizer_contact =
      if organizer && organizer["self"] != true && !is_resource_calendar?(organizer["email"]) do
        parse_organizer(organizer, event)
      end

    [organizer_contact | attendee_contacts]
  end

  defp is_resource_calendar?(nil), do: true

  defp is_resource_calendar?(email) do
    # Resource calendars typically have specific patterns
    String.contains?(email, "resource.calendar.google.com") ||
      String.contains?(email, "@group.calendar.google.com")
  end

  defp parse_attendee(attendee, event) do
    email = attendee["email"]
    display_name = attendee["displayName"]

    if email do
      %{
        name: display_name || extract_name_from_email(email),
        email: email,
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: "gcal:#{email}",
        metadata: %{
          source: "google_calendar",
          last_meeting: event["start"]["dateTime"] || event["start"]["date"],
          response_status: attendee["responseStatus"]
        }
      }
    end
  end

  defp parse_organizer(organizer, event) do
    email = organizer["email"]
    display_name = organizer["displayName"]

    if email do
      %{
        name: display_name || extract_name_from_email(email),
        email: email,
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: "gcal:#{email}",
        metadata: %{
          source: "google_calendar",
          last_meeting: event["start"]["dateTime"] || event["start"]["date"],
          is_organizer: true
        }
      }
    end
  end

  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp client_id do
    config()[:client_id] || raise "Google Calendar OAuth client_id not configured"
  end

  defp client_secret do
    config()[:client_secret] || raise "Google Calendar OAuth client_secret not configured"
  end

  defp config do
    # Use same Google OAuth config as Google Contacts
    Application.get_env(:conezia, :google_oauth, [])
  end
end
