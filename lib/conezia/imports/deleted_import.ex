defmodule Conezia.Imports.DeletedImport do
  @moduledoc """
  Schema for tracking deleted imports.

  When a user deletes an entity that was imported from an external service,
  we record the external ID here so that future syncs don't re-import it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "deleted_imports" do
    field :external_id, :string
    field :source, :string
    field :entity_name, :string
    field :entity_email, :string

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :external_id, :source]
  @optional_fields [:entity_name, :entity_email]

  def changeset(deleted_import, attrs) do
    deleted_import
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :external_id, :source])
  end
end
