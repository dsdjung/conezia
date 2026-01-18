defmodule Conezia.Entities.Relationship do
  @moduledoc """
  Relationship schema representing the connection between a user and an entity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @relationship_types ~w(friend family colleague client vendor acquaintance service_provider other)
  @strength_levels ~w(close regular acquaintance)
  @statuses ~w(active inactive archived)

  schema "relationships" do
    field :type, :string
    field :strength, :string, default: "regular"
    field :status, :string, default: "active"
    field :started_at, :date
    field :health_threshold_days, :integer, default: 30
    field :notes, :string

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :entity_id]
  @optional_fields [:type, :strength, :status, :started_at, :health_threshold_days, :notes]

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @relationship_types)
    |> validate_inclusion(:strength, @strength_levels)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:health_threshold_days, greater_than: 0, less_than_or_equal_to: 365)
    |> validate_length(:notes, max: 5000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
    |> unique_constraint([:user_id, :entity_id])
  end

  def valid_types, do: @relationship_types
  def valid_strengths, do: @strength_levels
  def valid_statuses, do: @statuses
end
