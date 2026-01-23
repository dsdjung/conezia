defmodule Conezia.Platform.Webhook do
  @moduledoc """
  Webhook schema for third-party application event subscriptions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @events ~w(entity.created entity.updated entity.deleted
             communication.sent reminder.due reminder.completed
             import.completed)
  @statuses ~w(active paused failed)

  schema "webhooks" do
    field :url, :string
    field :events, {:array, :string}, default: []
    field :secret, Conezia.Encrypted.Binary
    field :status, :string, default: "active"
    field :last_triggered_at, :utc_datetime_usec
    field :failure_count, :integer, default: 0

    belongs_to :application, Conezia.Platform.Application
    has_many :deliveries, Conezia.Platform.WebhookDelivery

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:url, :events, :application_id]
  @optional_fields [:status, :last_triggered_at, :failure_count]

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_url(:url)
    |> validate_events()
    |> validate_inclusion(:status, @statuses)
    |> generate_secret()
    |> foreign_key_constraint(:application_id)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: "https", host: host} when not is_nil(host) ->
          []
        _ ->
          [{field, "must be a valid HTTPS URL"}]
      end
    end)
  end

  defp validate_events(changeset) do
    validate_change(changeset, :events, fn :events, events ->
      if events == [] do
        [events: "must have at least one event"]
      else
        invalid = events -- @events
        if invalid == [] do
          []
        else
          [events: "contains invalid events: #{inspect(invalid)}"]
        end
      end
    end)
  end

  defp generate_secret(changeset) do
    if !get_field(changeset, :secret) do
      secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      put_change(changeset, :secret, secret)
    else
      changeset
    end
  end

  def valid_events, do: @events
  def valid_statuses, do: @statuses
end
