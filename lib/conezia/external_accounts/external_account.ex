defmodule Conezia.ExternalAccounts.ExternalAccount do
  @moduledoc """
  External account schema for OAuth connections to third-party services.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @services ~w(google icloud outlook linkedin facebook)
  @statuses ~w(connected disconnected error pending_reauth)

  schema "external_accounts" do
    field :service_name, :string
    field :account_identifier, :string
    field :credentials, :binary
    field :refresh_token, :binary
    field :status, :string, default: "connected"
    field :scopes, {:array, :string}, default: []
    field :last_synced_at, :utc_datetime_usec
    field :sync_error, :string
    field :metadata, :map, default: %{}
    field :token_expires_at, :utc_datetime_usec
    field :last_token_refresh_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:service_name, :account_identifier, :user_id]
  @optional_fields [:credentials, :refresh_token, :status, :scopes, :last_synced_at,
                    :sync_error, :metadata, :entity_id, :token_expires_at,
                    :last_token_refresh_at]

  def changeset(external_account, attrs) do
    external_account
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:service_name, @services)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:account_identifier, max: 255)
    |> unique_constraint([:user_id, :service_name, :account_identifier])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  def mark_error_changeset(external_account, error_message) do
    change(external_account,
      status: "error",
      sync_error: error_message
    )
  end

  def mark_synced_changeset(external_account) do
    change(external_account,
      status: "connected",
      last_synced_at: DateTime.utc_now(),
      sync_error: nil
    )
  end

  def valid_services, do: @services
  def valid_statuses, do: @statuses
end
