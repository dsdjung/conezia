defmodule Conezia.Validators.CrossField do
  @moduledoc """
  Cross-field and business rule validations that span multiple fields or entities.
  """
  import Ecto.Changeset
  import Ecto.Query

  @doc """
  Validates that if recurrence is set, the due_at must be reasonable
  for the frequency.
  """
  def validate_recurrence_and_due_at(changeset) do
    recurrence = get_field(changeset, :recurrence_rule)
    due_at = get_field(changeset, :due_at)

    if recurrence && due_at do
      freq = Map.get(recurrence, "freq")
      interval = Map.get(recurrence, "interval", 1)

      min_interval = case freq do
        "daily" -> 1
        "weekly" -> 7
        "monthly" -> 28
        "yearly" -> 365
        _ -> 1
      end * interval

      # Warn if due date is very far in the past for recurring
      days_ago = DateTime.diff(DateTime.utc_now(), due_at, :day)

      if days_ago > min_interval * 10 do
        add_error(changeset, :due_at,
          "recurring reminder due date is very far in the past")
      else
        changeset
      end
    else
      changeset
    end
  end

  @doc """
  Validates that entity type and relationship type are compatible.
  """
  def validate_entity_relationship_compatibility(changeset) do
    entity_type = get_field(changeset, :entity_type)
    relationship_type = get_field(changeset, :relationship_type)

    incompatible = %{
      "thing" => ["friend", "family", "colleague"],
      "service" => ["friend", "family"],
      "abstract" => ["friend", "family", "colleague", "client"]
    }

    invalid_types = Map.get(incompatible, entity_type, [])

    if relationship_type in invalid_types do
      add_error(changeset, :relationship_type,
        "#{relationship_type} is not valid for #{entity_type} entities")
    else
      changeset
    end
  end

  @doc """
  Validates smart group rules reference valid tags.
  """
  def validate_smart_group_tag_references(changeset, user_id) do
    rules = get_field(changeset, :rules)
    tag_names = get_in(rules, ["tags"]) || []

    if tag_names != [] do
      existing_tags = Conezia.Repo.all(
        from t in Conezia.Entities.Tag,
        where: t.user_id == ^user_id and t.name in ^tag_names,
        select: t.name
      )

      missing = tag_names -- existing_tags

      if missing != [] do
        add_error(changeset, :rules,
          "references non-existent tags: #{Enum.join(missing, ", ")}")
      else
        changeset
      end
    else
      changeset
    end
  end

  @doc """
  Validates that communication entity belongs to the same user.
  """
  def validate_entity_ownership(changeset, user_id) do
    entity_id = get_field(changeset, :entity_id)

    if entity_id do
      entity = Conezia.Repo.get(Conezia.Entities.Entity, entity_id)

      cond do
        is_nil(entity) ->
          add_error(changeset, :entity_id, "entity does not exist")
        entity.owner_id != user_id ->
          add_error(changeset, :entity_id, "entity does not belong to user")
        true ->
          changeset
      end
    else
      changeset
    end
  end

  @doc """
  Validates that a conversation belongs to the same user and entity.
  """
  def validate_conversation_consistency(changeset) do
    conversation_id = get_field(changeset, :conversation_id)
    entity_id = get_field(changeset, :entity_id)
    user_id = get_field(changeset, :user_id)

    if conversation_id do
      conversation = Conezia.Repo.get(Conezia.Communications.Conversation, conversation_id)

      cond do
        is_nil(conversation) ->
          add_error(changeset, :conversation_id, "conversation does not exist")
        conversation.user_id != user_id ->
          add_error(changeset, :conversation_id, "conversation does not belong to user")
        entity_id && conversation.entity_id != entity_id ->
          add_error(changeset, :conversation_id, "conversation is for a different entity")
        true ->
          changeset
      end
    else
      changeset
    end
  end

  @doc """
  Validates that an identifier is unique for the given entity.
  """
  def validate_unique_identifier_for_entity(changeset) do
    entity_id = get_field(changeset, :entity_id)
    type = get_field(changeset, :type)
    value = get_field(changeset, :value)
    id = get_field(changeset, :id)

    if entity_id && type && value do
      query = from i in Conezia.Entities.Identifier,
        where: i.entity_id == ^entity_id and i.type == ^type and i.value == ^value

      query = if id, do: where(query, [i], i.id != ^id), else: query

      if Conezia.Repo.exists?(query) do
        add_error(changeset, :value, "identifier already exists for this entity")
      else
        changeset
      end
    else
      changeset
    end
  end
end
