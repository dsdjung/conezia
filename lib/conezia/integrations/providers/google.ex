defmodule Conezia.Integrations.Providers.Google do
  @moduledoc """
  Unified Google integration combining Contacts, Calendar, and Gmail.

  This module implements the ServiceProvider behaviour to fetch contacts
  from multiple Google services with a single OAuth connection:
  - Google Contacts (People API)
  - Google Calendar (Calendar API) - extracts contacts from meeting attendees
  - Gmail (Gmail API) - extracts contacts from email communications

  All three data sources are fetched with a single OAuth token, providing
  a seamless user experience.
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_people_api "https://people.googleapis.com/v1"
  @google_calendar_api "https://www.googleapis.com/calendar/v3"
  @gmail_api "https://gmail.googleapis.com/gmail/v1"

  # Email patterns to filter out (automated, noreply, etc.)
  @filtered_email_patterns [
    ~r/noreply@/i,
    ~r/no-reply@/i,
    ~r/donotreply@/i,
    ~r/notifications?@/i,
    ~r/alert@/i,
    ~r/mailer-daemon@/i,
    ~r/postmaster@/i,
    ~r/bounce@/i,
    ~r/support@.*\.com$/i,
    ~r/newsletter@/i,
    ~r/updates@/i
  ]

  @impl true
  def service_name, do: "google"

  @impl true
  def display_name, do: "Google"

  @impl true
  def icon, do: "hero-cloud"

  @impl true
  def scopes do
    # Combined scopes for all Google services
    [
      "https://www.googleapis.com/auth/contacts.readonly",
      "https://www.googleapis.com/auth/calendar.readonly",
      "https://www.googleapis.com/auth/gmail.readonly"
    ]
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
    # Fetch from all three sources - each source fails gracefully
    # so if one API fails, we still get contacts from the others
    contacts_result = fetch_from_contacts(access_token, opts)
    calendar_result = fetch_from_calendar(access_token)
    gmail_result = fetch_from_gmail(access_token)

    # Extract successful results, defaulting to empty list on failure
    contacts_data = case contacts_result do
      {:ok, data} -> data
      {:error, _} -> []
    end

    calendar_data = case calendar_result do
      {:ok, data} -> data
      {:error, _} -> []
    end

    gmail_data = case gmail_result do
      {:ok, data} -> data
      {:error, _} -> []
    end

    # If all three failed, return an error
    all_failed? = match?({:error, _}, contacts_result) and
                  match?({:error, _}, calendar_result) and
                  match?({:error, _}, gmail_result)

    if all_failed? do
      # Return the first error message
      {:error, _reason} = contacts_result
      contacts_result
    else
      # Merge and deduplicate all contacts from successful sources
      all_contacts =
        (contacts_data ++ calendar_data ++ gmail_data)
        |> deduplicate_contacts()

      {:ok, all_contacts, nil}
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

  # ============================================================================
  # Google Contacts (People API)
  # ============================================================================

  defp fetch_from_contacts(access_token, opts) do
    page_size = Keyword.get(opts, :page_size, 100)
    page_token = Keyword.get(opts, :page_token)

    params = %{
      personFields: "names,emailAddresses,phoneNumbers,organizations,biographies,photos",
      pageSize: page_size
    }

    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@google_people_api}/people/me/connections?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        contacts = parse_people_connections(body["connections"] || [])
        {:ok, contacts}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        # Contacts scope may not be granted, return empty
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch contacts (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  defp parse_people_connections(connections) do
    Enum.map(connections, &parse_people_connection/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_people_connection(connection) do
    name = get_primary_value(connection["names"], "displayName")

    if name do
      %{
        name: name,
        email: get_primary_value(connection["emailAddresses"], "value"),
        phone: get_primary_value(connection["phoneNumbers"], "value"),
        organization: get_primary_value(connection["organizations"], "name"),
        notes: get_first_value(connection["biographies"], "value"),
        external_id: connection["resourceName"],
        metadata: %{
          photo_url: get_first_value(connection["photos"], "url"),
          source: "google_contacts"
        }
      }
    end
  end

  defp get_primary_value(nil, _key), do: nil

  defp get_primary_value(items, key) do
    primary = Enum.find(items, List.first(items), &(&1["metadata"]["primary"] == true))
    primary && primary[key]
  end

  defp get_first_value(nil, _key), do: nil
  defp get_first_value([], _key), do: nil
  defp get_first_value([item | _], key), do: item[key]

  # ============================================================================
  # Google Calendar
  # ============================================================================

  defp fetch_from_calendar(access_token) do
    # Fetch events from the past year for more comprehensive contact history
    time_min =
      DateTime.utc_now()
      |> DateTime.add(-365, :day)
      |> DateTime.to_iso8601()

    time_max = DateTime.utc_now() |> DateTime.to_iso8601()

    # Fetch all calendar events with pagination
    fetch_all_calendar_events(access_token, time_min, time_max, nil, [])
  end

  defp fetch_all_calendar_events(access_token, time_min, time_max, page_token, accumulated) do
    params = %{
      timeMin: time_min,
      timeMax: time_max,
      maxResults: 500,
      singleEvents: true,
      orderBy: "startTime"
    }

    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@google_calendar_api}/calendars/primary/events?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        contacts = extract_calendar_contacts(body["items"] || [])
        all_contacts = accumulated ++ contacts

        case body["nextPageToken"] do
          nil ->
            {:ok, all_contacts}

          next_token ->
            fetch_all_calendar_events(access_token, time_min, time_max, next_token, all_contacts)
        end

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        # Calendar scope may not be granted, return empty
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch calendar events (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  defp extract_calendar_contacts(events) do
    events
    |> Enum.flat_map(&extract_event_attendees/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_event_attendees(event) do
    attendees = event["attendees"] || []
    organizer = event["organizer"]

    attendee_contacts =
      Enum.map(attendees, fn attendee ->
        if attendee["self"] != true && !is_resource_calendar?(attendee["email"]) do
          parse_calendar_attendee(attendee, event)
        end
      end)

    organizer_contact =
      if organizer && organizer["self"] != true && !is_resource_calendar?(organizer["email"]) do
        parse_calendar_organizer(organizer, event)
      end

    [organizer_contact | attendee_contacts]
  end

  defp is_resource_calendar?(nil), do: true

  defp is_resource_calendar?(email) do
    String.contains?(email, "resource.calendar.google.com") ||
      String.contains?(email, "@group.calendar.google.com")
  end

  defp parse_calendar_attendee(attendee, event) do
    email = attendee["email"]

    if email do
      %{
        name: attendee["displayName"] || extract_name_from_email(email),
        email: email,
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: "gcal:#{String.downcase(email)}",
        metadata: %{
          source: "google_calendar",
          last_meeting: event["start"]["dateTime"] || event["start"]["date"],
          response_status: attendee["responseStatus"]
        }
      }
    end
  end

  defp parse_calendar_organizer(organizer, event) do
    email = organizer["email"]

    if email do
      %{
        name: organizer["displayName"] || extract_name_from_email(email),
        email: email,
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: "gcal:#{String.downcase(email)}",
        metadata: %{
          source: "google_calendar",
          last_meeting: event["start"]["dateTime"] || event["start"]["date"],
          is_organizer: true
        }
      }
    end
  end

  # ============================================================================
  # Gmail
  # ============================================================================

  defp fetch_from_gmail(access_token) do
    # Fetch messages from the past year for comprehensive contact history
    after_date =
      Date.utc_today()
      |> Date.add(-365)
      |> Date.to_iso8601()
      |> String.replace("-", "/")

    query = "after:#{after_date}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    # Fetch message IDs with pagination
    case fetch_all_gmail_message_ids(headers, query, nil, []) do
      {:ok, message_ids} ->
        contacts = fetch_gmail_contacts_from_messages(message_ids, headers)
        {:ok, contacts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all_gmail_message_ids(headers, query, page_token, accumulated) do
    params = %{q: query, maxResults: 500}
    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@gmail_api}/users/me/messages?#{URI.encode_query(params)}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        message_ids = Enum.map(body["messages"] || [], & &1["id"])
        all_ids = accumulated ++ message_ids

        # Limit total messages to 2000 to avoid excessive API calls
        # Each message requires a separate API call to fetch headers
        if length(all_ids) >= 2000 do
          {:ok, Enum.take(all_ids, 2000)}
        else
          case body["nextPageToken"] do
            nil ->
              {:ok, all_ids}

            next_token ->
              fetch_all_gmail_message_ids(headers, query, next_token, all_ids)
          end
        end

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        # Gmail scope may not be granted, return empty
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch messages (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Gmail: #{inspect(reason)}"}
    end
  end

  defp fetch_gmail_contacts_from_messages(message_ids, headers) do
    # Process messages in batches to extract contacts
    # Limit to 500 messages to balance completeness with API rate limits
    message_ids
    |> Enum.take(500)
    |> Enum.flat_map(fn id -> fetch_gmail_message_contacts(id, headers) end)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_gmail_message_contacts(message_id, headers) do
    url = "#{@gmail_api}/users/me/messages/#{message_id}?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        extract_gmail_contacts_from_headers(body)

      _ ->
        []
    end
  end

  defp extract_gmail_contacts_from_headers(message) do
    headers = message["payload"]["headers"] || []
    internal_date = message["internalDate"]

    date =
      if internal_date do
        internal_date
        |> String.to_integer()
        |> DateTime.from_unix!(:millisecond)
        |> DateTime.to_iso8601()
      end

    from_header = find_header(headers, "From")
    to_header = find_header(headers, "To")

    from_contacts = parse_gmail_addresses(from_header, date, :received)
    to_contacts = parse_gmail_addresses(to_header, date, :sent)

    from_contacts ++ to_contacts
  end

  defp find_header(headers, name) do
    case Enum.find(headers, &(&1["name"] == name)) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp parse_gmail_addresses(nil, _date, _direction), do: []

  defp parse_gmail_addresses(header, date, direction) do
    header
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_single_email_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&filtered_email?/1)
    |> Enum.map(fn {name, email} ->
      %{
        name: name || extract_name_from_email(email),
        email: String.downcase(email),
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: "gmail:#{String.downcase(email)}",
        metadata: %{
          source: "gmail",
          last_email_date: date,
          direction: direction
        }
      }
    end)
  end

  defp parse_single_email_address(address) do
    case Regex.run(~r/^(?:([^<]+)\s*)?<?([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>?$/, String.trim(address)) do
      [_, name, email] ->
        name = if name && String.trim(name) != "", do: String.trim(name), else: nil
        {name, email}

      [_, email] ->
        {nil, email}

      _ ->
        nil
    end
  end

  defp filtered_email?({_name, email}) do
    Enum.any?(@filtered_email_patterns, &Regex.match?(&1, email))
  end

  # ============================================================================
  # Common Helpers
  # ============================================================================

  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp deduplicate_contacts(contacts) do
    # Deduplicate by email, preferring contacts with more data
    contacts
    |> Enum.group_by(fn contact ->
      if contact.email, do: String.downcase(contact.email), else: contact.external_id
    end)
    |> Enum.map(fn {_key, group} ->
      # Pick the contact with the most complete data
      Enum.max_by(group, fn contact ->
        score = 0
        score = if contact.name, do: score + 1, else: score
        score = if contact.email, do: score + 1, else: score
        score = if contact.phone, do: score + 2, else: score
        score = if contact.organization, do: score + 1, else: score
        score = if contact.metadata[:photo_url], do: score + 1, else: score
        # Prefer google_contacts as the primary source
        score = if contact.metadata.source == "google_contacts", do: score + 10, else: score
        score
      end)
    end)
  end

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
