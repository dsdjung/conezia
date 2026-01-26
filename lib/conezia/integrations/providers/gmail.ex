defmodule Conezia.Integrations.Providers.Gmail do
  @moduledoc """
  Gmail integration using the Gmail API.

  This module implements the ServiceProvider behaviour to extract contacts
  from email communications. It identifies people the user has emailed
  or received emails from, tracking "last contacted" information.

  Key features:
  - Extracts contacts from sent and received emails
  - Tracks last email date for each contact
  - Deduplicates by email address
  - Filters out automated/noreply addresses
  """

  @behaviour Conezia.Integrations.ServiceProvider

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @gmail_api "https://gmail.googleapis.com/gmail/v1"

  # Email patterns to filter out (automated, noreply, etc.)
  @filtered_patterns [
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
  def service_name, do: "gmail"

  @impl true
  def display_name, do: "Gmail"

  @impl true
  def icon, do: "hero-envelope"

  @impl true
  def scopes do
    # readonly access to email metadata (not content)
    ["https://www.googleapis.com/auth/gmail.readonly"]
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
    max_results = Keyword.get(opts, :page_size, 100)

    # Fetch messages from the past 90 days
    after_date =
      Date.utc_today()
      |> Date.add(-90)
      |> Date.to_iso8601()
      |> String.replace("-", "/")

    # Query for sent and received emails
    query = "after:#{after_date}"

    params = %{
      q: query,
      maxResults: max_results
    }

    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@gmail_api}/users/me/messages?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        message_ids = Enum.map(body["messages"] || [], & &1["id"])
        contacts = fetch_contacts_from_messages(access_token, message_ids)
        next_page_token = body["nextPageToken"]
        {:ok, contacts, next_page_token}

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied - check scopes"}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch messages (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Gmail: #{inspect(reason)}"}
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

  defp fetch_contacts_from_messages(access_token, message_ids) do
    headers = [{"authorization", "Bearer #{access_token}"}]

    # Fetch message headers in batches to extract email addresses
    message_ids
    |> Enum.take(50)  # Limit to avoid rate limits
    |> Enum.flat_map(fn id -> fetch_message_contacts(access_token, id, headers) end)
    |> Enum.reject(&is_nil/1)
    |> deduplicate_contacts()
  end

  defp fetch_message_contacts(_access_token, message_id, headers) do
    url = "#{@gmail_api}/users/me/messages/#{message_id}?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        extract_contacts_from_headers(body)

      _ ->
        []
    end
  end

  defp extract_contacts_from_headers(message) do
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

    from_contacts = parse_email_addresses(from_header, date, :received)
    to_contacts = parse_email_addresses(to_header, date, :sent)

    from_contacts ++ to_contacts
  end

  defp find_header(headers, name) do
    case Enum.find(headers, &(&1["name"] == name)) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp parse_email_addresses(nil, _date, _direction), do: []

  defp parse_email_addresses(header, date, direction) do
    # Parse email addresses from header like "John Doe <john@example.com>, jane@example.com"
    header
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_single_address/1)
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

  defp parse_single_address(address) do
    # Handle formats like "John Doe <john@example.com>" or just "john@example.com"
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
    Enum.any?(@filtered_patterns, &Regex.match?(&1, email))
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
    # Keep the contact with the most recent email date for each email address
    contacts
    |> Enum.group_by(& &1.email)
    |> Enum.map(fn {_email, group} ->
      Enum.max_by(group, fn contact ->
        contact.metadata[:last_email_date] || ""
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
    # Use same Google OAuth config as other Google services
    Application.get_env(:conezia, :google_oauth, [])
  end
end
