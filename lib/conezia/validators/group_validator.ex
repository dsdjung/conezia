defmodule Conezia.Validators.GroupValidator do
  @moduledoc """
  Validation rules for group data including smart group rules.
  """
  import Ecto.Changeset

  @valid_rule_fields ~w(type tags relationship_type relationship_status last_interaction_days)
  @max_groups_per_user 50

  def validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_not_blank(:name)
    |> unique_constraint([:user_id, :name],
        message: "group with this name already exists")
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 500)
  end

  def validate_smart_rules(changeset) do
    is_smart = get_field(changeset, :is_smart)
    rules = get_field(changeset, :rules)

    cond do
      is_smart && (is_nil(rules) || rules == %{}) ->
        add_error(changeset, :rules, "is required for smart groups")
      is_smart ->
        validate_rules_structure(changeset, rules)
      !is_smart && rules && rules != %{} ->
        add_error(changeset, :rules, "should not be provided for non-smart groups")
      true ->
        changeset
    end
  end

  defp validate_rules_structure(changeset, rules) do
    errors = []

    # Check for invalid rule fields
    invalid_fields = Map.keys(rules) -- @valid_rule_fields
    errors = if invalid_fields != [] do
      [{:rules, "contains invalid fields: #{Enum.join(invalid_fields, ", ")}"} | errors]
    else
      errors
    end

    # Validate last_interaction_days if present
    errors = case Map.get(rules, "last_interaction_days") do
      nil -> errors
      days when is_integer(days) and days > 0 and days <= 365 -> errors
      _ -> [{:rules, "last_interaction_days must be 1-365"} | errors]
    end

    # Validate tags if present
    errors = case Map.get(rules, "tags") do
      nil -> errors
      tags when is_list(tags) -> errors
      _ -> [{:rules, "tags must be a list"} | errors]
    end

    Enum.reduce(errors, changeset, fn {field, msg}, cs ->
      add_error(cs, field, msg)
    end)
  end

  def validate_group_limit(user_id) do
    import Ecto.Query

    count = Conezia.Repo.aggregate(
      from(g in Conezia.Entities.Group, where: g.user_id == ^user_id),
      :count
    )

    if count >= @max_groups_per_user do
      {:error, "maximum of #{@max_groups_per_user} groups allowed"}
    else
      :ok
    end
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end

  def valid_rule_fields, do: @valid_rule_fields
  def max_groups_per_user, do: @max_groups_per_user
end
