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
      "https://www.googleapis.com/auth/contacts.other.readonly",
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

  defp fetch_from_contacts(access_token, _opts) do
    # Fetch from both "My Contacts" and "Other Contacts"
    # "Other Contacts" contains auto-created contacts from email interactions
    my_contacts = fetch_all_contacts_pages(access_token, nil, [])
    other_contacts = fetch_all_other_contacts_pages(access_token, nil, [])

    case {my_contacts, other_contacts} do
      {{:ok, my}, {:ok, other}} ->
        {:ok, my ++ other}

      {{:ok, my}, {:error, _}} ->
        # Other contacts failed but we have my contacts
        {:ok, my}

      {{:error, _}, {:ok, other}} ->
        # My contacts failed but we have other contacts
        {:ok, other}

      {{:error, reason}, {:error, _}} ->
        {:error, reason}
    end
  end

  defp fetch_all_contacts_pages(access_token, page_token, accumulated) do
    params = %{
      personFields: "names,emailAddresses,phoneNumbers,organizations,biographies,photos",
      pageSize: 1000
    }

    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@google_people_api}/people/me/connections?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        contacts = parse_people_connections(body["connections"] || [])
        all_contacts = accumulated ++ contacts

        case body["nextPageToken"] do
          nil ->
            {:ok, all_contacts}

          next_token ->
            fetch_all_contacts_pages(access_token, next_token, all_contacts)
        end

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

  # Fetch "Other Contacts" - auto-created contacts from email interactions
  defp fetch_all_other_contacts_pages(access_token, page_token, accumulated) do
    params = %{
      readMask: "names,emailAddresses,phoneNumbers",
      pageSize: 1000
    }

    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@google_people_api}/otherContacts?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        contacts = parse_other_contacts(body["otherContacts"] || [])
        all_contacts = accumulated ++ contacts

        case body["nextPageToken"] do
          nil ->
            {:ok, all_contacts}

          next_token ->
            fetch_all_other_contacts_pages(access_token, next_token, all_contacts)
        end

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        # Other contacts scope may not be granted, return empty
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch other contacts (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Google: #{inspect(reason)}"}
    end
  end

  defp parse_other_contacts(contacts) do
    Enum.map(contacts, &parse_other_contact/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_other_contact(contact) do
    name = get_primary_value(contact["names"], "displayName") |> sanitize_name()

    # For other contacts, fall back to email-derived name if no display name
    email = get_primary_value(contact["emailAddresses"], "value")
    name = name || (email && extract_name_from_email(email))

    if name do
      resource_name = contact["resourceName"]
      %{
        name: name,
        email: email,
        phone: get_primary_value(contact["phoneNumbers"], "value"),
        organization: nil,
        notes: nil,
        external_id: resource_name,
        metadata: %{
          source: "google_contacts",
          sources: ["google_contacts"],
          external_ids: %{"google_contacts" => resource_name}
        }
      }
    end
  end

  defp parse_people_connections(connections) do
    Enum.map(connections, &parse_people_connection/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_people_connection(connection) do
    name = get_primary_value(connection["names"], "displayName") |> sanitize_name()

    if name do
      resource_name = connection["resourceName"]
      %{
        name: name,
        email: get_primary_value(connection["emailAddresses"], "value"),
        phone: get_primary_value(connection["phoneNumbers"], "value"),
        organization: get_primary_value(connection["organizations"], "name"),
        notes: get_first_value(connection["biographies"], "value"),
        external_id: resource_name,
        metadata: %{
          photo_url: get_first_value(connection["photos"], "url"),
          source: "google_contacts",
          sources: ["google_contacts"],
          external_ids: %{"google_contacts" => resource_name}
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
      external_id = "gcal:#{String.downcase(email)}"
      %{
        name: sanitize_name(attendee["displayName"]) || extract_name_from_email(email),
        email: email,
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: external_id,
        metadata: %{
          source: "google_calendar",
          sources: ["google_calendar"],
          external_ids: %{"google_calendar" => external_id},
          last_meeting: event["start"]["dateTime"] || event["start"]["date"],
          response_status: attendee["responseStatus"]
        }
      }
    end
  end

  defp parse_calendar_organizer(organizer, event) do
    email = organizer["email"]

    if email do
      external_id = "gcal:#{String.downcase(email)}"
      %{
        name: sanitize_name(organizer["displayName"]) || extract_name_from_email(email),
        email: email,
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: external_id,
        metadata: %{
          source: "google_calendar",
          sources: ["google_calendar"],
          external_ids: %{"google_calendar" => external_id},
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
      external_id = "gmail:#{String.downcase(email)}"
      %{
        name: name || extract_name_from_email(email),
        email: String.downcase(email),
        phone: nil,
        organization: nil,
        notes: nil,
        external_id: external_id,
        metadata: %{
          source: "gmail",
          sources: ["gmail"],
          external_ids: %{"gmail" => external_id},
          last_email_date: date,
          direction: direction
        }
      }
    end)
  end

  defp parse_single_email_address(address) do
    case Regex.run(~r/^(?:([^<]+)\s*)?<?([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>?$/, String.trim(address)) do
      [_, name, email] ->
        name = if name && String.trim(name) != "" do
          name
          |> String.trim()
          |> strip_surrounding_quotes()
        else
          nil
        end
        {name, email}

      [_, email] ->
        {nil, email}

      _ ->
        nil
    end
  end

  # Remove leading/trailing quotes and angle brackets from a string
  # Handles: "Name", 'Name', <Name>, Name", "Name, Name>, <Name, etc.
  defp strip_surrounding_quotes(str) do
    str
    |> String.trim_leading("\"")
    |> String.trim_leading("'")
    |> String.trim_leading("<")
    |> String.trim_trailing("\"")
    |> String.trim_trailing("'")
    |> String.trim_trailing(">")
    |> String.trim()
  end

  defp filtered_email?({_name, email}) do
    Enum.any?(@filtered_email_patterns, &Regex.match?(&1, email))
  end

  # ============================================================================
  # Common Helpers
  # ============================================================================

  # Sanitize a name by removing surrounding quotes and trimming whitespace
  defp sanitize_name(nil), do: nil
  defp sanitize_name(name) do
    name
    |> String.trim()
    |> strip_surrounding_quotes()
    |> case do
      "" -> nil
      sanitized -> sanitized
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

  defp deduplicate_contacts(contacts) do
    # Deduplicate contacts using a priority system:
    # 1. Email (most reliable)
    # 2. Phone number (for contacts without email)
    # 3. Normalized name (last resort for contacts without email/phone)
    # 4. External ID (unique within source, fallback)
    contacts
    |> Enum.group_by(&dedup_key/1)
    |> Enum.map(fn {_key, group} ->
      # Pick the contact with the most complete data and merge metadata from all
      merge_contact_group(group)
    end)
  end

  defp merge_contact_group([single]), do: single
  defp merge_contact_group(group) do
    # Sort by completeness score to pick best as primary
    sorted = Enum.sort_by(group, &contact_completeness_score/1, :desc)
    primary = hd(sorted)
    others = tl(sorted)

    # Merge all external_ids and sources from duplicates
    merged_external_ids =
      Enum.reduce(group, %{}, fn contact, acc ->
        contact_ids = contact.metadata[:external_ids] || %{}
        # Also include the legacy external_id if present
        contact_ids = if contact.external_id do
          source = contact.metadata[:source] || "unknown"
          Map.put_new(contact_ids, source, contact.external_id)
        else
          contact_ids
        end
        Map.merge(acc, contact_ids)
      end)

    merged_sources =
      group
      |> Enum.flat_map(fn c -> c.metadata[:sources] || [c.metadata[:source]] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # Merge metadata, keeping primary's values but adding external_ids/sources
    merged_metadata =
      primary.metadata
      |> Map.put(:external_ids, merged_external_ids)
      |> Map.put(:sources, merged_sources)

    # Also merge any missing fields from others
    merged = Enum.reduce(others, primary, fn other, acc ->
      acc
      |> maybe_merge_field(:phone, other)
      |> maybe_merge_field(:organization, other)
      |> maybe_merge_field(:notes, other)
    end)

    # Always prefer the longest/most complete name from the group
    best_name = find_best_name(group)
    merged = if best_name && best_name != merged.name do
      %{merged | name: best_name}
    else
      merged
    end

    %{merged | metadata: merged_metadata}
  end

  @doc false
  # Made public for testing - finds the most complete name from a group
  def find_best_name(contacts) do
    contacts
    |> Enum.map(& &1.name)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.max_by(fn name ->
      parts = String.split(name)
      # Prefer names with more parts (first + last) and longer overall length
      {length(parts), String.length(name)}
    end, fn -> nil end)
  end

  defp maybe_merge_field(contact, field, other) do
    if is_nil(Map.get(contact, field)) && Map.get(other, field) do
      Map.put(contact, field, Map.get(other, field))
    else
      contact
    end
  end

  defp dedup_key(contact) do
    cond do
      contact.email ->
        {:email, String.downcase(contact.email)}

      contact.phone ->
        {:phone, normalize_phone(contact.phone)}

      contact.name && String.trim(contact.name) != "" ->
        {:name, normalize_name(contact.name)}

      contact.external_id ->
        {:external_id, contact.external_id}

      true ->
        # Unique key for contacts with no identifying info (shouldn't happen often)
        {:random, :erlang.unique_integer()}
    end
  end

  defp normalize_phone(phone) do
    # Remove all non-digit characters for comparison
    String.replace(phone, ~r/[^\d]/, "")
  end

  defp normalize_name(name) do
    name
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
  end

  @doc false
  # Made public for testing - calculates how "complete" a contact is for deduplication
  def contact_completeness_score(contact) do
    score = 0

    # Name completeness - prefer longer, more complete names
    # This is important: "David Oh" should beat "Oh" when merging
    score = case contact.name do
      nil -> score
      name ->
        name_parts = name |> String.trim() |> String.split()
        # Base point for having a name
        score = score + 1
        # Bonus for having multiple name parts (first + last name)
        score = score + min(length(name_parts) - 1, 2) * 5
        # Small bonus for name length (capped to avoid very long names dominating)
        score + min(String.length(name), 30)
    end

    score = if contact.email, do: score + 1, else: score
    score = if contact.phone, do: score + 2, else: score
    score = if contact.organization, do: score + 1, else: score
    score = if contact.metadata[:photo_url], do: score + 1, else: score
    # Prefer google_contacts as the primary source (but not enough to override name completeness)
    if contact.metadata.source == "google_contacts", do: score + 3, else: score
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
