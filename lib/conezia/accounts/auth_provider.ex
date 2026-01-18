defmodule Conezia.Accounts.AuthProvider do
  @moduledoc """
  OAuth provider association for users.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(google apple facebook linkedin)

  schema "auth_providers" do
    field :provider, :string
    field :provider_uid, :string
    field :provider_token, :binary
    field :provider_refresh_token, :binary
    field :provider_meta, :map, default: %{}

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(auth_provider, attrs) do
    auth_provider
    |> cast(attrs, [:provider, :provider_uid, :provider_token, :provider_refresh_token, :provider_meta, :user_id])
    |> validate_required([:provider, :provider_uid, :user_id])
    |> validate_inclusion(:provider, @providers)
    |> unique_constraint([:provider, :provider_uid])
    |> foreign_key_constraint(:user_id)
  end

  def valid_providers, do: @providers
end
