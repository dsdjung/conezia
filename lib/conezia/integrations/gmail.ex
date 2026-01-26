defmodule Conezia.Integrations.Gmail do
  @moduledoc """
  Gmail API helper functions for on-demand email queries.

  This module provides functions to query Gmail directly for specific
  information, such as finding the last email with a particular contact.
  """

  alias Conezia.Integrations

  require Logger

  @gmail_api "https://gmail.googleapis.com/gmail/v1"

  @doc """
  Fetches the last email with a contact for a given user.

  Returns `{:ok, email_info}` with email details, or `{:error, reason}`.

  The returned email_info contains:
  - subject: Email subject line
  - date: DateTime when the email was sent/received
  - direction: "inbound" or "outbound"
  - snippet: Short preview of email content
  """
  def get_last_email_with_contact(user_id, contact_email) when is_binary(contact_email) do
    with {:ok, account} <- get_google_account(user_id),
         {:ok, refreshed_account} <- Integrations.refresh_tokens_if_needed(account),
         {:ok, access_token} <- Integrations.get_access_token(refreshed_account) do
      fetch_last_email(access_token, contact_email, user_id)
    end
  end

  @doc """
  Returns the last emails with multiple contacts at once.

  Takes a list of email addresses and returns a map of email -> email_info.
  This is more efficient than calling get_last_email_with_contact multiple times.
  """
  def get_last_emails_with_contacts(user_id, contact_emails) when is_list(contact_emails) do
    with {:ok, account} <- get_google_account(user_id),
         {:ok, refreshed_account} <- Integrations.refresh_tokens_if_needed(account),
         {:ok, access_token} <- Integrations.get_access_token(refreshed_account) do
      # Fetch in parallel for efficiency
      results =
        contact_emails
        |> Task.async_stream(
          fn email -> {email, fetch_last_email(access_token, email, user_id)} end,
          max_concurrency: 5,
          timeout: 10_000,
          on_timeout: :kill_task
        )
        |> Enum.reduce(%{}, fn
          {:ok, {email, {:ok, info}}}, acc -> Map.put(acc, email, info)
          {:ok, {email, {:error, _}}}, acc -> Map.put(acc, email, nil)
          {:exit, _}, acc -> acc
        end)

      {:ok, results}
    end
  end

  @doc """
  Checks if the user has a connected Google account with Gmail access.
  """
  def has_gmail_access?(user_id) do
    case get_google_account(user_id) do
      {:ok, _account} -> true
      {:error, _} -> false
    end
  end

  # Private functions

  defp get_google_account(user_id) do
    case Integrations.get_connected_account(user_id, "google") do
      nil ->
        # Also check for "google_contacts" service name for backwards compatibility
        case Integrations.get_connected_account(user_id, "google_contacts") do
          nil -> {:error, :no_google_account}
          account -> {:ok, account}
        end

      account ->
        {:ok, account}
    end
  end

  defp fetch_last_email(access_token, contact_email, user_id) do
    # Get the user's email to determine direction
    user = Conezia.Repo.get(Conezia.Accounts.User, user_id)
    user_email = user && String.downcase(user.email)

    # Query for emails involving this contact
    query = "from:#{contact_email} OR to:#{contact_email}"
    params = %{q: query, maxResults: 1}

    url = "#{@gmail_api}/users/me/messages?#{URI.encode_query(params)}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"messages" => [%{"id" => message_id} | _]}}} ->
        fetch_message_details(access_token, message_id, contact_email, user_email)

      {:ok, %{status: 200, body: %{"resultSizeEstimate" => 0}}} ->
        {:error, :no_emails_found}

      {:ok, %{status: 200, body: %{}}} ->
        {:error, :no_emails_found}

      {:ok, %{status: 401}} ->
        {:error, :token_expired}

      {:ok, %{status: 403}} ->
        {:error, :gmail_access_denied}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        Logger.warning("Gmail API error: status=#{status} error=#{error}")
        {:error, {:api_error, status, error}}

      {:error, reason} ->
        Logger.warning("Gmail API connection error: #{inspect(reason)}")
        {:error, {:connection_error, reason}}
    end
  end

  defp fetch_message_details(access_token, message_id, contact_email, user_email) do
    url = "#{@gmail_api}/users/me/messages/#{message_id}?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Subject&metadataHeaders=Date"
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_message_response(body, message_id, contact_email, user_email)

      {:ok, %{status: _}} ->
        {:error, :message_fetch_failed}

      {:error, _} ->
        {:error, :message_fetch_failed}
    end
  end

  defp parse_message_response(body, message_id, contact_email, user_email) do
    headers = body["payload"]["headers"] || []
    internal_date = body["internalDate"]
    snippet = body["snippet"]
    thread_id = body["threadId"]

    from_header = find_header(headers, "From")
    to_header = find_header(headers, "To")
    subject = find_header(headers, "Subject")

    # Parse the date
    date =
      if internal_date do
        internal_date
        |> String.to_integer()
        |> DateTime.from_unix!(:millisecond)
      else
        nil
      end

    # Determine direction based on who sent it
    from_email = extract_email_from_header(from_header)
    direction = determine_direction(from_email, contact_email, user_email)

    # Build Gmail URL to open this message
    gmail_url = "https://mail.google.com/mail/u/0/#inbox/#{thread_id || message_id}"

    {:ok, %{
      message_id: message_id,
      thread_id: thread_id,
      subject: subject,
      date: date,
      direction: direction,
      snippet: snippet,
      from: from_header,
      to: to_header,
      gmail_url: gmail_url
    }}
  end

  defp find_header(headers, name) do
    case Enum.find(headers, &(&1["name"] == name)) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp extract_email_from_header(nil), do: nil
  defp extract_email_from_header(header) do
    case Regex.run(~r/<([^>]+)>|([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/, header) do
      [_, email, ""] -> String.downcase(email)
      [_, "", email] -> String.downcase(email)
      [_, email] -> String.downcase(email)
      _ -> nil
    end
  end

  defp determine_direction(from_email, contact_email, user_email) do
    contact_email_lower = String.downcase(contact_email)

    cond do
      from_email == contact_email_lower -> "inbound"
      from_email == user_email -> "outbound"
      true -> "inbound"  # Default to inbound if unclear
    end
  end
end
