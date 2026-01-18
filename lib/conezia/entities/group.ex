defmodule Conezia.Entities.Group do
  @moduledoc """
  Group schema for organizing entities, including smart groups with dynamic rules.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "groups" do
    field :name, :string
    field :description, :string
    field :is_smart, :boolean, default: false
    field :rules, :map

    belongs_to :user, Conezia.Accounts.User
    many_to_many :entities, Conezia.Entities.Entity, join_through: "entity_groups"

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :user_id]
  @optional_fields [:description, :is_smart, :rules]

  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_smart_group_rules()
    |> unique_constraint([:user_id, :name])
    |> foreign_key_constraint(:user_id)
  end

  defp validate_smart_group_rules(changeset) do
    is_smart = get_field(changeset, :is_smart)
    rules = get_field(changeset, :rules)

    cond do
      is_smart and (is_nil(rules) or rules == %{}) ->
        add_error(changeset, :rules, "is required for smart groups")
      is_smart ->
        validate_rules_schema(changeset, rules)
      true ->
        changeset
    end
  end

  defp validate_rules_schema(changeset, rules) do
    valid_fields = ~w(type tags relationship_type relationship_status last_interaction_days)

    case rules do
      %{} = r when map_size(r) > 0 ->
        invalid_keys = Map.keys(r) -- valid_fields
        if invalid_keys == [] do
          changeset
        else
          add_error(changeset, :rules, "contains invalid fields: #{inspect(invalid_keys)}")
        end
      _ ->
        add_error(changeset, :rules, "must be a valid rules object")
    end
  end
end
