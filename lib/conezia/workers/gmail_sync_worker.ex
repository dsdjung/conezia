defmodule Conezia.Workers.GmailSyncWorker do
  @moduledoc """
  Oban worker for syncing Gmail messages as Communications.

  This worker fetches email messages from Gmail and stores them as
  Communications linked to the corresponding entities based on email addresses.
  """
  use Oban.Worker, queue: :sync, max_attempts: 3

  alias Conezia.Communications
  alias Conezia.Entities
  alias Conezia.ExternalAccounts
  alias Conezia.Integrations
  alias Conezia.Repo

  require Logger

  @gmail_api "https://gmail.googleapis.com/gmail/v1"
  @pubsub Conezia.PubSub
  @topic_prefix "gmail_sync:"

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

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"external_account_id" => account_id, "user_id" => user_id} = args}) do
    days_back = Map.get(args, "days_back", 30)
    max_messages = Map.get(args, "max_messages", 500)

    case ExternalAccounts.get_external_account(account_id) do
      nil ->
        {:error, :external_account_not_found}

      account ->
        if account.user_id != user_id do
          {:error, :unauthorized}
        else
          process_gmail_sync(account, user_id, days_back, max_messages)
        end
    end
  end

  defp process_gmail_sync(account, user_id, days_back, max_messages) do
    broadcast_status(user_id, :started, %{account_id: account.id})

    try do
      with {:ok, refreshed_account} <- Integrations.refresh_tokens_if_needed(account),
           {:ok, access_token} <- Integrations.get_access_token(refreshed_account) do
        result = fetch_and_import_messages(user_id, access_token, days_back, max_messages)

        case result do
          {:ok, stats} ->
            ExternalAccounts.mark_synced(refreshed_account)
            broadcast_status(user_id, :completed, %{
              account_id: account.id,
              stats: stats
            })
            :ok

          {:error, reason} ->
            ExternalAccounts.mark_error(refreshed_account, to_string(reason))
            broadcast_status(user_id, :failed, %{
              account_id: account.id,
              error: to_string(reason)
            })
            {:error, reason}
        end
      else
        {:error, reason} ->
          broadcast_status(user_id, :failed, %{
            account_id: account.id,
            error: to_string(reason)
          })
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Gmail sync worker error: #{Exception.message(e)}")
        broadcast_status(user_id, :failed, %{
          account_id: account.id,
          error: Exception.message(e)
        })
        {:error, e}
    end
  end

  defp broadcast_status(user_id, status, payload) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}#{user_id}", {:gmail_sync_status, status, payload})
  end

  @doc """
  Returns the PubSub topic for a user's Gmail sync updates.
  """
  def topic(user_id), do: "#{@topic_prefix}#{user_id}"

  defp fetch_and_import_messages(user_id, access_token, days_back, max_messages) do
    # Build date query
    after_date =
      Date.utc_today()
      |> Date.add(-days_back)
      |> Date.to_iso8601()
      |> String.replace("-", "/")

    query = "after:#{after_date}"
    headers = [{"authorization", "Bearer #{access_token}"}]

    # Fetch message IDs
    case fetch_message_ids(headers, query, max_messages) do
      {:ok, message_ids} ->
        import_messages(user_id, message_ids, headers, access_token)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_message_ids(headers, query, max_messages, page_token \\ nil, accumulated \\ []) do
    params = %{q: query, maxResults: min(500, max_messages)}
    params = if page_token, do: Map.put(params, :pageToken, page_token), else: params

    url = "#{@gmail_api}/users/me/messages?#{URI.encode_query(params)}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        message_ids = Enum.map(body["messages"] || [], & &1["id"])
        all_ids = accumulated ++ message_ids

        if length(all_ids) >= max_messages do
          {:ok, Enum.take(all_ids, max_messages)}
        else
          case body["nextPageToken"] do
            nil ->
              {:ok, all_ids}

            next_token ->
              fetch_message_ids(headers, query, max_messages, next_token, all_ids)
          end
        end

      {:ok, %{status: 401}} ->
        {:error, "Token expired or invalid"}

      {:ok, %{status: 403}} ->
        {:error, "Gmail access not authorized"}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, "Failed to fetch messages (#{status}): #{error}"}

      {:error, reason} ->
        {:error, "Failed to connect to Gmail: #{inspect(reason)}"}
    end
  end

  defp import_messages(user_id, message_ids, headers, _access_token) do
    total = length(message_ids)

    stats =
      message_ids
      |> Task.async_stream(
        fn id -> fetch_and_create_communication(user_id, id, headers) end,
        max_concurrency: 10,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{imported: 0, skipped: 0, linked: 0, errors: 0}, fn result, acc ->
        case result do
          {:ok, {:ok, :imported, true}} -> %{acc | imported: acc.imported + 1, linked: acc.linked + 1}
          {:ok, {:ok, :imported, false}} -> %{acc | imported: acc.imported + 1}
          {:ok, {:ok, :skipped}} -> %{acc | skipped: acc.skipped + 1}
          {:ok, {:error, _}} -> %{acc | errors: acc.errors + 1}
          {:exit, _} -> %{acc | errors: acc.errors + 1}
        end
      end)

    {:ok, Map.put(stats, :total, total)}
  end

  defp fetch_and_create_communication(user_id, message_id, headers) do
    url = "#{@gmail_api}/users/me/messages/#{message_id}?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Subject&metadataHeaders=Date"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        create_communication_from_message(user_id, body)

      {:ok, %{status: _}} ->
        {:ok, :skipped}

      {:error, _} ->
        {:ok, :skipped}
    end
  end

  defp create_communication_from_message(user_id, message) do
    msg_headers = message["payload"]["headers"] || []
    internal_date = message["internalDate"]
    gmail_id = message["id"]
    thread_id = message["threadId"]

    # Check if we already have this message
    if Communications.get_communication_by_external_id(gmail_id) do
      {:ok, :skipped}
    else
      # Parse headers
      from_header = find_header(msg_headers, "From")
      to_header = find_header(msg_headers, "To")
      subject = find_header(msg_headers, "Subject")

      # Parse email addresses
      from_parsed = parse_email_address(from_header)
      to_parsed = parse_email_addresses(to_header)

      # Determine direction and contact email
      # If we sent the email, the contact is in To; otherwise contact is in From
      {direction, contact_email, contact_name} = determine_direction_and_contact(user_id, from_parsed, to_parsed)

      # Skip if contact email is filtered
      if contact_email && filtered_email?(contact_email) do
        {:ok, :skipped}
      else
        # Find entity by email
        entity = if contact_email, do: Entities.find_by_email(user_id, contact_email), else: nil

        # Parse date
        sent_at =
          if internal_date do
            internal_date
            |> String.to_integer()
            |> DateTime.from_unix!(:millisecond)
          else
            DateTime.utc_now()
          end

        # Create communication
        attrs = %{
          "direction" => direction,
          "channel" => "email",
          "subject" => subject,
          "content" => build_content_summary(subject, contact_name, contact_email),
          "sent_at" => sent_at,
          "external_id" => gmail_id,
          "user_id" => user_id,
          "entity_id" => entity && entity.id,
          "metadata" => %{
            "thread_id" => thread_id,
            "from" => from_header,
            "to" => to_header
          }
        }

        case Communications.create_communication(attrs) do
          {:ok, _comm} ->
            # Update entity's last_interaction_at if linked
            if entity do
              Entities.touch_entity_interaction(entity)
            end
            {:ok, :imported, entity != nil}

          {:error, _changeset} ->
            {:error, "Failed to create communication"}
        end
      end
    end
  end

  defp find_header(headers, name) do
    case Enum.find(headers, &(&1["name"] == name)) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp parse_email_address(nil), do: nil
  defp parse_email_address(header) do
    case Regex.run(~r/^(?:([^<]+)\s*)?<?([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>?$/, String.trim(header)) do
      [_, name, email] ->
        name = if name && String.trim(name) != "" do
          name
          |> String.trim()
          |> strip_surrounding_quotes()
        else
          nil
        end
        {name, String.downcase(email)}

      [_, email] ->
        {nil, String.downcase(email)}

      _ ->
        nil
    end
  end

  # Remove surrounding double or single quotes from a string
  defp strip_surrounding_quotes(str) do
    str
    |> String.trim("\"")
    |> String.trim("'")
  end

  defp parse_email_addresses(nil), do: []
  defp parse_email_addresses(header) do
    header
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_email_address/1)
    |> Enum.reject(&is_nil/1)
  end

  defp determine_direction_and_contact(user_id, from_parsed, to_parsed) do
    # Get user's email addresses to determine direction
    user = Repo.get(Conezia.Accounts.User, user_id)
    user_email = user && String.downcase(user.email)

    case from_parsed do
      {_name, email} when email == user_email ->
        # User sent this email - contact is first recipient
        case to_parsed do
          [{to_name, to_email} | _] -> {"outbound", to_email, to_name}
          _ -> {"outbound", nil, nil}
        end

      {name, email} ->
        # User received this email - contact is sender
        {"inbound", email, name}

      nil ->
        # Can't determine
        {"inbound", nil, nil}
    end
  end

  defp filtered_email?(email) do
    Enum.any?(@filtered_email_patterns, &Regex.match?(&1, email))
  end

  defp build_content_summary(subject, contact_name, contact_email) do
    parts = []
    parts = if subject, do: ["Subject: #{subject}" | parts], else: parts
    parts = if contact_name, do: ["Contact: #{contact_name}" | parts], else: parts
    parts = if contact_email, do: ["Email: #{contact_email}" | parts], else: parts
    Enum.join(Enum.reverse(parts), "\n")
  end
end
