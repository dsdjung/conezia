defmodule Conezia.Platform.ApplicationUser do
  @moduledoc """
  ApplicationUser schema for tracking user authorizations to third-party applications.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "application_users" do
    field :external_user_id, :string
    field :granted_scopes, {:array, :string}, default: []
    field :authorized_at, :utc_datetime_usec
    field :last_accessed_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :application, Conezia.Platform.Application
    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:application_id, :user_id]
  @optional_fields [:external_user_id, :granted_scopes, :authorized_at, :last_accessed_at, :revoked_at]

  def changeset(app_user, attrs) do
    app_user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_scopes()
    |> put_authorized_at()
    |> unique_constraint([:application_id, :user_id])
    |> foreign_key_constraint(:application_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_scopes(changeset) do
    valid_scopes = Conezia.Platform.Application.valid_scopes()
    validate_change(changeset, :granted_scopes, fn :granted_scopes, scopes ->
      invalid = scopes -- valid_scopes
      if invalid == [], do: [], else: [granted_scopes: "contains invalid scopes"]
    end)
  end

  defp put_authorized_at(changeset) do
    if get_change(changeset, :application_id) && !get_field(changeset, :authorized_at) do
      put_change(changeset, :authorized_at, DateTime.utc_now())
    else
      changeset
    end
  end

  def update_access_changeset(app_user) do
    change(app_user, last_accessed_at: DateTime.utc_now())
  end

  def revoke_changeset(app_user) do
    change(app_user, revoked_at: DateTime.utc_now())
  end
end
