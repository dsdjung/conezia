defmodule Conezia.Platform.WebhookDelivery do
  @moduledoc """
  WebhookDelivery schema for tracking webhook delivery attempts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webhook_deliveries" do
    field :event_type, :string
    field :payload, :map
    field :response_status, :integer
    field :response_body, :string
    field :delivered_at, :utc_datetime_usec

    belongs_to :webhook, Conezia.Platform.Webhook

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:event_type, :payload, :webhook_id]
  @optional_fields [:response_status, :response_body, :delivered_at]

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:webhook_id)
  end
end
