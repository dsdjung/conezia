defmodule Conezia.Integrations.Providers.ICloudCalendar do
  @moduledoc """
  iCloud Calendar integration using Apple's CalDAV protocol.

  This module implements calendar sync for iCloud using CalDAV (RFC 4791).
  Authentication uses app-specific passwords, similar to iCloud Contacts.

  Users need to:
  1. Enable two-factor authentication on their Apple ID
  2. Generate an app-specific password at appleid.apple.com
  3. Use their Apple ID email and the app-specific password to connect
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @caldav_url "https://caldav.icloud.com"

  @impl true
  def service_name, do: "icloud_calendar"

  @impl true
  def display_name, do: "iCloud Calendar"

  @impl true
  def icon, do: "hero-calendar"

  @impl true
  def scopes do
    ["calendar"]
  end

  @impl true
  def authorize_url(_redirect_uri, _state) do
    # iCloud doesn't use standard OAuth
    # Return a special URL that our frontend handles differently
    "icloud://calendar-auth"
  end

  @impl true
  def exchange_code(credentials_json, _redirect_uri) do
    case Jason.decode(credentials_json) do
      {:ok, %{"apple_id" => apple_id, "app_password" => app_password}} ->
        case verify_credentials(apple_id, app_password) do
          :ok ->
            {:ok,
             %{
               access_token: app_password,
               refresh_token: apple_id,
               expires_in: nil,
               token_type: "Basic"
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, _} ->
        {:error, "Invalid credentials format - expected apple_id and app_password"}

      {:error, _} ->
        {:error, "Invalid credentials format - expected JSON"}
    end
  end

  @impl true
  def refresh_token(_apple_id) do
    {:error, "iCloud uses app-specific passwords which don't need refreshing. Please reconnect if access is revoked."}
  end

  @impl true
  def fetch_contacts(_access_token, _opts) do
    {:error, "This provider is for calendar sync only, use icloud for contacts"}
  end

  @impl true
  def revoke_access(_access_token) do
    :ok
  end

  # ============================================================================
  # Calendar Sync Functions
  # ============================================================================

  @doc """
  Fetches calendar events from iCloud Calendar.
  """
  def fetch_calendar_events(app_password, opts \\ []) do
    apple_id = Keyword.get(opts, :apple_id) || Keyword.get(opts, :refresh_token)

    unless apple_id do
      {:error, "Apple ID required for iCloud requests"}
    else
      fetch_caldav_events(apple_id, app_password, opts)
    end
  end

  @doc """
  Creates a new event in iCloud Calendar.
  """
  def create_calendar_event(app_password, apple_id, event_data) do
    auth = Base.encode64("#{apple_id}:#{app_password}")
    headers = [
      {"authorization", "Basic #{auth}"},
      {"content-type", "text/calendar; charset=utf-8"}
    ]

    uid = generate_uid()
    ical = generate_icalendar(event_data, uid)

    case get_calendar_path(headers) do
      {:ok, calendar_path} ->
        url = "#{@caldav_url}#{calendar_path}#{uid}.ics"

        case Req.put(url, headers: headers, body: ical) do
          {:ok, %{status: status}} when status in [200, 201, 204] ->
            {:ok, %{external_id: uid, etag: nil}}

          {:ok, %{status: 401}} ->
            {:error, "Invalid Apple ID or app-specific password"}

          {:ok, %{status: status, body: body}} ->
            {:error, "Failed to create event (#{status}): #{inspect(body)}"}

          {:error, reason} ->
            {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an existing event in iCloud Calendar.
  """
  def update_calendar_event(app_password, apple_id, event_uid, event_data) do
    auth = Base.encode64("#{apple_id}:#{app_password}")
    headers = [
      {"authorization", "Basic #{auth}"},
      {"content-type", "text/calendar; charset=utf-8"}
    ]

    ical = generate_icalendar(event_data, event_uid)

    case get_calendar_path(headers) do
      {:ok, calendar_path} ->
        url = "#{@caldav_url}#{calendar_path}#{event_uid}.ics"

        case Req.put(url, headers: headers, body: ical) do
          {:ok, %{status: status}} when status in [200, 201, 204] ->
            {:ok, %{external_id: event_uid, etag: nil}}

          {:ok, %{status: 401}} ->
            {:error, "Invalid Apple ID or app-specific password"}

          {:ok, %{status: 404}} ->
            {:error, "Event not found"}

          {:ok, %{status: status, body: body}} ->
            {:error, "Failed to update event (#{status}): #{inspect(body)}"}

          {:error, reason} ->
            {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes an event from iCloud Calendar.
  """
  def delete_calendar_event(app_password, apple_id, event_uid) do
    auth = Base.encode64("#{apple_id}:#{app_password}")
    headers = [{"authorization", "Basic #{auth}"}]

    case get_calendar_path(headers) do
      {:ok, calendar_path} ->
        url = "#{@caldav_url}#{calendar_path}#{event_uid}.ics"

        case Req.delete(url, headers: headers) do
          {:ok, %{status: status}} when status in [200, 204, 404, 410] ->
            :ok

          {:ok, %{status: 401}} ->
            {:error, "Invalid Apple ID or app-specific password"}

          {:ok, %{status: status, body: body}} ->
            {:error, "Failed to delete event (#{status}): #{inspect(body)}"}

          {:error, reason} ->
            {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp verify_credentials(apple_id, app_password) do
    auth = Base.encode64("#{apple_id}:#{app_password}")
    headers = [
      {"authorization", "Basic #{auth}"},
      {"content-type", "application/xml; charset=utf-8"},
      {"depth", "0"}
    ]

    propfind_body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:current-user-principal/>
      </d:prop>
    </d:propfind>
    """

    case Req.request(
           method: :propfind,
           url: @caldav_url,
           headers: headers,
           body: propfind_body
         ) do
      {:ok, %{status: status}} when status in [200, 207] ->
        :ok

      {:ok, %{status: 401}} ->
        {:error, "Invalid Apple ID or app-specific password"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied - ensure two-factor authentication is enabled"}

      {:ok, %{status: status, body: body}} ->
        {:error, "iCloud verification failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
    end
  end

  defp fetch_caldav_events(apple_id, app_password, opts) do
    auth = Base.encode64("#{apple_id}:#{app_password}")
    headers = [
      {"authorization", "Basic #{auth}"},
      {"content-type", "application/xml; charset=utf-8"},
      {"depth", "1"}
    ]

    time_min = Keyword.get(opts, :time_min) || DateTime.utc_now() |> DateTime.add(-365, :day)
    time_max = Keyword.get(opts, :time_max) || DateTime.utc_now() |> DateTime.add(365, :day)

    case get_calendar_path(headers) do
      {:ok, calendar_path} ->
        fetch_events_from_calendar(calendar_path, headers, time_min, time_max)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_calendar_path(headers) do
    propfind_body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:prop>
        <c:calendar-home-set/>
      </d:prop>
    </d:propfind>
    """

    case Req.request(
           method: :propfind,
           url: @caldav_url,
           headers: headers,
           body: propfind_body
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 207] ->
        case parse_calendar_home(body) do
          nil -> {:ok, "/"}
          path -> {:ok, path}
        end

      {:ok, %{status: status}} ->
        {:error, "Failed to get calendar home (#{status})"}

      {:error, reason} ->
        {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
    end
  end

  defp parse_calendar_home(xml_body) when is_binary(xml_body) do
    case Regex.run(~r/<d:href>([^<]+)<\/d:href>/i, xml_body) do
      [_, href] -> href
      _ -> nil
    end
  end

  defp parse_calendar_home(_), do: nil

  defp fetch_events_from_calendar(calendar_path, headers, time_min, time_max) do
    time_min_str = format_ical_datetime(time_min)
    time_max_str = format_ical_datetime(time_max)

    report_body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:prop>
        <d:getetag/>
        <c:calendar-data/>
      </d:prop>
      <c:filter>
        <c:comp-filter name="VCALENDAR">
          <c:comp-filter name="VEVENT">
            <c:time-range start="#{time_min_str}" end="#{time_max_str}"/>
          </c:comp-filter>
        </c:comp-filter>
      </c:filter>
    </c:calendar-query>
    """

    url = "#{@caldav_url}#{calendar_path}"

    case Req.request(
           method: :report,
           url: url,
           headers: headers ++ [{"depth", "1"}],
           body: report_body
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 207] ->
        events = parse_caldav_response(body)
        {:ok, events, nil}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to fetch events (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to connect to iCloud: #{inspect(reason)}"}
    end
  end

  defp parse_caldav_response(body) when is_binary(body) do
    ~r/<c:calendar-data[^>]*>([\s\S]*?)<\/c:calendar-data>/i
    |> Regex.scan(body)
    |> Enum.map(fn [_, ical] -> parse_icalendar(ical) end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_caldav_response(_), do: []

  defp parse_icalendar(ical_text) do
    lines = String.split(ical_text, ~r/\r?\n/)

    uid = extract_ical_field(lines, "UID")
    summary = extract_ical_field(lines, "SUMMARY")
    description = extract_ical_field(lines, "DESCRIPTION")
    location = extract_ical_field(lines, "LOCATION")
    dtstart = extract_ical_field(lines, "DTSTART")
    dtend = extract_ical_field(lines, "DTEND")

    if uid && summary do
      %{
        external_id: uid,
        title: summary,
        description: description,
        location: location,
        starts_at: parse_ical_datetime(dtstart),
        ends_at: parse_ical_datetime(dtend),
        all_day: dtstart && String.length(dtstart) == 8,
        etag: nil
      }
    end
  end

  defp extract_ical_field(lines, field_name) do
    pattern = ~r/^#{field_name}(?:;[^:]+)?:(.+)$/i

    Enum.find_value(lines, fn line ->
      case Regex.run(pattern, String.trim(line)) do
        [_, value] -> String.trim(value)
        _ -> nil
      end
    end)
  end

  defp parse_ical_datetime(nil), do: nil

  defp parse_ical_datetime(dt_string) do
    cond do
      # All-day date: 20260128
      String.length(dt_string) == 8 ->
        case Date.from_iso8601("#{String.slice(dt_string, 0, 4)}-#{String.slice(dt_string, 4, 2)}-#{String.slice(dt_string, 6, 2)}") do
          {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          _ -> nil
        end

      # DateTime with Z: 20260128T100000Z
      String.ends_with?(dt_string, "Z") ->
        parse_ical_datetime_utc(String.trim_trailing(dt_string, "Z"))

      # DateTime without Z (assume UTC)
      String.contains?(dt_string, "T") ->
        parse_ical_datetime_utc(dt_string)

      true ->
        nil
    end
  end

  defp parse_ical_datetime_utc(dt_string) do
    # Format: 20260128T100000
    date_str = "#{String.slice(dt_string, 0, 4)}-#{String.slice(dt_string, 4, 2)}-#{String.slice(dt_string, 6, 2)}"
    time_str = "#{String.slice(dt_string, 9, 2)}:#{String.slice(dt_string, 11, 2)}:#{String.slice(dt_string, 13, 2)}"

    case DateTime.from_iso8601("#{date_str}T#{time_str}Z") do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp format_ical_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y%m%dT%H%M%SZ")
  end

  defp generate_uid do
    "#{UUID.uuid4()}@conezia.com"
  end

  defp generate_icalendar(event_data, uid) do
    now = DateTime.utc_now() |> format_ical_datetime()
    title = event_data[:title] || event_data["title"] || "Untitled"
    description = event_data[:description] || event_data["description"]
    location = event_data[:location] || event_data["location"]
    starts_at = event_data[:starts_at] || event_data["starts_at"]
    ends_at = event_data[:ends_at] || event_data["ends_at"]
    all_day = event_data[:all_day] || event_data["all_day"] || false

    dtstart = if starts_at do
      if all_day do
        "DTSTART;VALUE=DATE:#{Calendar.strftime(starts_at, "%Y%m%d")}"
      else
        "DTSTART:#{format_ical_datetime(starts_at)}"
      end
    end

    dtend = if ends_at do
      if all_day do
        "DTEND;VALUE=DATE:#{Calendar.strftime(ends_at, "%Y%m%d")}"
      else
        "DTEND:#{format_ical_datetime(ends_at)}"
      end
    else
      if starts_at && all_day do
        end_date = starts_at |> DateTime.to_date() |> Date.add(1)
        "DTEND;VALUE=DATE:#{Calendar.strftime(end_date, "%Y%m%d")}"
      else
        nil
      end
    end

    lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Conezia//Calendar Sync//EN",
      "BEGIN:VEVENT",
      "UID:#{uid}",
      "DTSTAMP:#{now}",
      dtstart,
      dtend,
      "SUMMARY:#{escape_ical_text(title)}"
    ]

    lines = if description, do: lines ++ ["DESCRIPTION:#{escape_ical_text(description)}"], else: lines
    lines = if location, do: lines ++ ["LOCATION:#{escape_ical_text(location)}"], else: lines

    lines = lines ++ [
      "END:VEVENT",
      "END:VCALENDAR"
    ]

    lines
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\r\n")
  end

  defp escape_ical_text(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(",", "\\,")
    |> String.replace(";", "\\;")
    |> String.replace("\n", "\\n")
  end
end
