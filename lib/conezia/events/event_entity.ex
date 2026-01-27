defmodule Conezia.Events.EventEntity do
  @moduledoc """
  Join schema for linking events to entities with optional roles.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(host guest honoree organizer attendee participant)

  schema "event_entities" do
    field :role, :string

    belongs_to :event, Conezia.Events.Event
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:event_id, :entity_id]
  @optional_fields [:role]

  def changeset(event_entity, attrs) do
    event_entity
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> maybe_validate_role()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:entity_id)
    |> unique_constraint([:event_id, :entity_id])
  end

  defp maybe_validate_role(changeset) do
    case get_change(changeset, :role) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :role, @roles)
    end
  end

  def valid_roles, do: @roles
end
