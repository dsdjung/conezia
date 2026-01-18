defmodule Conezia.Workers.WebhookWorker do
  @moduledoc """
  Oban worker for delivering webhook events to registered endpoints.
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias Conezia.Platform.{Webhook, WebhookDelivery}
  alias Conezia.Repo
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_id" => webhook_id, "event_type" => event_type, "payload" => payload}}) do
    case Repo.get(Webhook, webhook_id) do
      nil ->
        {:error, :webhook_not_found}

      %Webhook{status: "paused"} ->
        {:cancel, :webhook_paused}

      %Webhook{status: "failed"} ->
        {:cancel, :webhook_failed}

      webhook ->
        deliver_webhook(webhook, event_type, payload)
    end
  end

  defp deliver_webhook(webhook, event_type, payload) do
    signature = compute_signature(webhook.secret, payload)

    headers = [
      {"content-type", "application/json"},
      {"x-webhook-signature", signature},
      {"x-webhook-event", event_type},
      {"x-webhook-id", webhook.id}
    ]

    body = Jason.encode!(%{
      event: event_type,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      data: payload
    })

    case Req.post(webhook.url, headers: headers, body: body, receive_timeout: 30_000) do
      {:ok, %{status: status}} when status >= 200 and status < 300 ->
        record_delivery(webhook, event_type, payload, status, nil)
        update_webhook_success(webhook)
        :ok

      {:ok, %{status: status, body: response_body}} ->
        record_delivery(webhook, event_type, payload, status, response_body)
        update_webhook_failure(webhook)
        {:error, "Webhook returned status #{status}"}

      {:error, reason} ->
        record_delivery(webhook, event_type, payload, nil, inspect(reason))
        update_webhook_failure(webhook)
        {:error, reason}
    end
  end

  defp compute_signature(secret, payload) do
    data = Jason.encode!(payload)
    :crypto.mac(:hmac, :sha256, secret, data)
    |> Base.encode16(case: :lower)
  end

  defp record_delivery(webhook, event_type, payload, status, response_body) do
    %WebhookDelivery{}
    |> WebhookDelivery.changeset(%{
      webhook_id: webhook.id,
      event_type: event_type,
      payload: payload,
      response_status: status,
      response_body: response_body && String.slice(response_body, 0, 10_000),
      delivered_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  defp update_webhook_success(webhook) do
    webhook
    |> Ecto.Changeset.change(%{
      last_triggered_at: DateTime.utc_now(),
      failure_count: 0
    })
    |> Repo.update()
  end

  defp update_webhook_failure(webhook) do
    new_failure_count = webhook.failure_count + 1

    changes = %{
      last_triggered_at: DateTime.utc_now(),
      failure_count: new_failure_count
    }

    # Mark as failed after 10 consecutive failures
    changes = if new_failure_count >= 10 do
      Map.put(changes, :status, "failed")
    else
      changes
    end

    webhook
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
  end

  @doc """
  Dispatch an event to all webhooks subscribed to this event type for an application.
  """
  def dispatch(application_id, event_type, payload) do
    webhooks = from(w in Webhook,
      where: w.application_id == ^application_id,
      where: w.status == "active",
      where: ^event_type in w.events
    )
    |> Repo.all()

    Enum.each(webhooks, fn webhook ->
      %{webhook_id: webhook.id, event_type: event_type, payload: payload}
      |> new()
      |> Oban.insert()
    end)

    {:ok, length(webhooks)}
  end

  @doc """
  Dispatch an event to all active webhooks subscribed to this event type.
  Used for system-wide events.
  """
  def broadcast(event_type, payload) do
    webhooks = from(w in Webhook,
      where: w.status == "active",
      where: ^event_type in w.events
    )
    |> Repo.all()

    Enum.each(webhooks, fn webhook ->
      %{webhook_id: webhook.id, event_type: event_type, payload: payload}
      |> new()
      |> Oban.insert()
    end)

    {:ok, length(webhooks)}
  end
end
