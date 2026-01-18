defmodule Conezia.Validators.PlatformValidator do
  @moduledoc """
  Validation rules for platform applications and webhooks.
  """
  import Ecto.Changeset
  import Ecto.Query

  @application_statuses ~w(pending approved suspended)
  @valid_scopes ~w(
    read:entities write:entities delete:entities
    read:communications write:communications
    read:reminders write:reminders
    read:profile write:profile
  )

  @valid_webhook_events ~w(
    entity.created entity.updated entity.deleted
    communication.sent
    reminder.due reminder.completed
    import.completed
  )
  @webhook_statuses ~w(active paused failed)
  @max_webhooks_per_app 20

  # Application validation

  def validate_application_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:name, ~r/^[\p{L}\p{N}\s\-_]+$/u,
        message: "can only contain letters, numbers, spaces, hyphens, and underscores")
  end

  def validate_application_description(changeset) do
    validate_length(changeset, :description, max: 1000)
  end

  def validate_application_urls(changeset) do
    changeset
    |> validate_url(:logo_url)
    |> validate_url(:website_url)
    |> validate_callback_urls()
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host}
            when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []
        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end

  defp validate_callback_urls(changeset) do
    validate_change(changeset, :callback_urls, fn :callback_urls, urls ->
      if is_list(urls) do
        urls
        |> Enum.with_index()
        |> Enum.flat_map(fn {url, index} ->
          case URI.parse(url) do
            %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
              []
            _ ->
              [callback_urls: "URL at position #{index + 1} must be a valid HTTPS URL"]
          end
        end)
      else
        [callback_urls: "must be a list of URLs"]
      end
    end)
  end

  def validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      if is_list(scopes) do
        invalid = scopes -- @valid_scopes
        if invalid == [] do
          []
        else
          [scopes: "contains invalid scopes: #{Enum.join(invalid, ", ")}"]
        end
      else
        [scopes: "must be a list of scope strings"]
      end
    end)
  end

  def validate_application_status(changeset) do
    validate_inclusion(changeset, :status, @application_statuses)
  end

  # Webhook validation

  def validate_webhook_url(changeset) do
    changeset
    |> validate_required([:url])
    |> validate_change(:url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
          # Don't allow localhost in production
          if Application.get_env(:conezia, :env) == :prod && host in ["localhost", "127.0.0.1"] do
            [url: "cannot use localhost in production"]
          else
            []
          end
        _ ->
          [url: "must be a valid HTTPS URL"]
      end
    end)
  end

  def validate_webhook_events(changeset) do
    changeset
    |> validate_required([:events])
    |> validate_change(:events, fn :events, events ->
      cond do
        !is_list(events) ->
          [events: "must be a list"]
        events == [] ->
          [events: "must have at least one event"]
        (invalid = events -- @valid_webhook_events) != [] ->
          [events: "contains invalid events: #{Enum.join(invalid, ", ")}"]
        true ->
          []
      end
    end)
  end

  def validate_webhook_status(changeset) do
    validate_inclusion(changeset, :status, @webhook_statuses)
  end

  def validate_webhook_limit(application_id) do
    count = Conezia.Repo.aggregate(
      from(w in Conezia.Platform.Webhook, where: w.application_id == ^application_id),
      :count
    )

    if count >= @max_webhooks_per_app do
      {:error, "maximum of #{@max_webhooks_per_app} webhooks per application"}
    else
      :ok
    end
  end

  def valid_scopes, do: @valid_scopes
  def valid_webhook_events, do: @valid_webhook_events
  def application_statuses, do: @application_statuses
  def webhook_statuses, do: @webhook_statuses
  def max_webhooks_per_app, do: @max_webhooks_per_app
end
