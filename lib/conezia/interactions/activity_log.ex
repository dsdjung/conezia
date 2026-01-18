defmodule Conezia.Interactions.ActivityLog do
  @moduledoc """
  Activity log for tracking user actions in the system.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(create update delete view export login logout import)
  @resource_types ~w(entity relationship communication interaction reminder tag group attachment user)

  schema "activity_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :user_agent, :string

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:action, :resource_type, :user_id]
  @optional_fields [:resource_id, :metadata, :ip_address, :user_agent]

  def changeset(activity_log, attrs) do
    activity_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:resource_type, @resource_types)
    |> foreign_key_constraint(:user_id)
  end

  def valid_actions, do: @actions
  def valid_resource_types, do: @resource_types
end
