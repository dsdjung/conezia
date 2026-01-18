defmodule Conezia.Entities.Tag do
  @moduledoc """
  Tag schema for categorizing entities.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @colors ~w(red orange yellow green blue purple pink gray)

  schema "tags" do
    field :name, :string
    field :color, :string, default: "blue"
    field :description, :string

    belongs_to :user, Conezia.Accounts.User
    many_to_many :entities, Conezia.Entities.Entity, join_through: "entity_tags"

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :user_id]
  @optional_fields [:color, :description]

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 50)
    |> validate_inclusion(:color, @colors)
    |> validate_length(:description, max: 255)
    |> unique_constraint([:user_id, :name])
    |> foreign_key_constraint(:user_id)
  end

  def valid_colors, do: @colors
end
