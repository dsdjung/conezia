defmodule Conezia.Entities do
  @moduledoc """
  The Entities context for managing contacts/entities and their relationships.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Entities.{Entity, Relationship, EntityRelationship, Identifier, Tag, Group, CustomField}

  # Entity functions

  def get_entity(id), do: Repo.get(Entity, id)

  def get_entity!(id), do: Repo.get!(Entity, id)

  def get_entity_for_user(id, user_id) do
    Entity
    |> where([e], e.id == ^id and e.owner_id == ^user_id)
    |> Repo.one()
  end

  def list_entities(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    type = Keyword.get(opts, :type)
    status = Keyword.get(opts, :status, "active")
    search = Keyword.get(opts, :search)

    query = from e in Entity,
      where: e.owner_id == ^user_id,
      limit: ^(limit + 1),
      offset: ^offset,
      order_by: [desc: e.last_interaction_at, desc: e.inserted_at]

    entities = query
    |> filter_by_type(type)
    |> filter_by_status(status)
    |> filter_by_search(search)
    |> Repo.all()

    # Check if there are more results
    has_more = length(entities) > limit
    entities = Enum.take(entities, limit)

    meta = %{
      has_more: has_more,
      next_cursor: if(has_more, do: offset + limit, else: nil)
    }

    {entities, meta}
  end

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [e], e.type == ^type)

  defp filter_by_status(query, "all"), do: query
  defp filter_by_status(query, "archived"), do: where(query, [e], not is_nil(e.archived_at))
  defp filter_by_status(query, _), do: where(query, [e], is_nil(e.archived_at))

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query
  defp filter_by_search(query, search) do
    search_term = "%#{search}%"
    where(query, [e], ilike(e.name, ^search_term) or ilike(e.description, ^search_term))
  end

  def count_user_entities(user_id) do
    Entity
    |> where([e], e.owner_id == ^user_id and is_nil(e.archived_at))
    |> Repo.aggregate(:count)
  end

  def create_entity(attrs) do
    %Entity{}
    |> Entity.changeset(attrs)
    |> Repo.insert()
  end

  def update_entity(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(attrs)
    |> Repo.update()
  end

  def archive_entity(%Entity{} = entity) do
    entity
    |> Entity.archive_changeset()
    |> Repo.update()
  end

  def unarchive_entity(%Entity{} = entity) do
    entity
    |> Entity.unarchive_changeset()
    |> Repo.update()
  end

  def delete_entity(%Entity{} = entity) do
    Repo.delete(entity)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking entity changes.
  """
  def change_entity(%Entity{} = entity, attrs \\ %{}) do
    Entity.changeset(entity, attrs)
  end

  def touch_entity_interaction(%Entity{} = entity) do
    entity
    |> Entity.touch_interaction_changeset()
    |> Repo.update()
  end

  def merge_entities(source_id, target_id, user_id, opts \\ []) do
    merge_identifiers = Keyword.get(opts, :merge_identifiers, true)
    merge_tags = Keyword.get(opts, :merge_tags, true)
    merge_interactions = Keyword.get(opts, :merge_interactions, true)

    Repo.transaction(fn ->
      source = get_entity_for_user(source_id, user_id)
      target = get_entity_for_user(target_id, user_id)

      cond do
        is_nil(source) -> Repo.rollback({:not_found, :source})
        is_nil(target) -> Repo.rollback({:not_found, :target})
        source.id == target.id -> Repo.rollback(:same_entity)
        source.type != target.type -> Repo.rollback(:type_mismatch)
        true ->
          summary = %{
            source_entity_id: source_id,
            identifiers_added: 0,
            tags_added: 0,
            interactions_transferred: 0
          }

          summary = if merge_identifiers, do: merge_entity_identifiers(source, target, summary), else: summary
          summary = if merge_tags, do: merge_entity_tags(source, target, summary), else: summary
          summary = if merge_interactions, do: merge_entity_interactions(source, target, summary), else: summary

          Repo.delete!(source)
          {Repo.get!(Entity, target_id), summary}
      end
    end)
  end

  defp merge_entity_identifiers(source, target, summary) do
    identifiers = Repo.all(from i in Identifier, where: i.entity_id == ^source.id)

    count = Enum.reduce(identifiers, 0, fn identifier, acc ->
      case Repo.update(Ecto.Changeset.change(identifier, entity_id: target.id)) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)

    Map.put(summary, :identifiers_added, count)
  end

  defp merge_entity_tags(source, target, summary) do
    # Get source entity tags
    source_tag_ids = Repo.all(
      from et in "entity_tags",
        where: et.entity_id == ^source.id,
        select: et.tag_id
    )

    existing_tag_ids = Repo.all(
      from et in "entity_tags",
        where: et.entity_id == ^target.id,
        select: et.tag_id
    )

    new_tag_ids = source_tag_ids -- existing_tag_ids

    # Convert string UUIDs to binary for raw table insert
    target_id_binary = Ecto.UUID.dump!(target.id)

    Enum.each(new_tag_ids, fn tag_id ->
      Repo.insert_all("entity_tags", [
        %{entity_id: target_id_binary, tag_id: tag_id, inserted_at: DateTime.utc_now()}
      ])
    end)

    Map.put(summary, :tags_added, length(new_tag_ids))
  end

  defp merge_entity_interactions(source, target, summary) do
    {count, _} = Repo.update_all(
      from(i in Conezia.Interactions.Interaction, where: i.entity_id == ^source.id),
      set: [entity_id: target.id]
    )

    Map.put(summary, :interactions_transferred, count)
  end

  # Relationship functions

  def get_relationship(id), do: Repo.get(Relationship, id)

  def get_relationship!(id), do: Repo.get!(Relationship, id)

  def get_relationship_for_entity(user_id, entity_id) do
    Repo.get_by(Relationship, user_id: user_id, entity_id: entity_id)
  end

  def list_relationships(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)
    type = Keyword.get(opts, :type)

    query = from r in Relationship,
      where: r.user_id == ^user_id,
      limit: ^limit,
      preload: [:entity]

    query
    |> filter_relationship_status(status)
    |> filter_relationship_type(type)
    |> Repo.all()
  end

  defp filter_relationship_status(query, nil), do: query
  defp filter_relationship_status(query, status), do: where(query, [r], r.status == ^status)

  defp filter_relationship_type(query, nil), do: query
  defp filter_relationship_type(query, type), do: where(query, [r], r.type == ^type)

  def create_relationship(attrs) do
    %Relationship{}
    |> Relationship.changeset(attrs)
    |> Repo.insert()
  end

  def update_relationship(%Relationship{} = relationship, attrs) do
    relationship
    |> Relationship.changeset(attrs)
    |> Repo.update()
  end

  def delete_relationship(%Relationship{} = relationship) do
    Repo.delete(relationship)
  end

  @doc """
  Get relationships for multiple entities at once.
  Returns a map of entity_id => relationship.
  """
  def get_relationships_for_entities(user_id, entity_ids) when is_list(entity_ids) do
    from(r in Relationship,
      where: r.user_id == ^user_id and r.entity_id in ^entity_ids
    )
    |> Repo.all()
    |> Map.new(fn r -> {r.entity_id, r} end)
  end

  # Identifier functions

  def get_identifier(id), do: Repo.get(Identifier, id)

  def get_identifier!(id), do: Repo.get!(Identifier, id)

  def list_identifiers_for_entity(entity_id) do
    Identifier
    |> where([i], i.entity_id == ^entity_id)
    |> order_by([i], [desc: i.is_primary, asc: i.type])
    |> Repo.all()
  end

  def create_identifier(attrs) do
    %Identifier{}
    |> Identifier.changeset(attrs)
    |> Repo.insert()
  end

  def update_identifier(%Identifier{} = identifier, attrs) do
    identifier
    |> Identifier.changeset(attrs)
    |> Repo.update()
  end

  def delete_identifier(%Identifier{} = identifier) do
    Repo.delete(identifier)
  end

  def check_identifier_duplicates(type, value) do
    # Use the same blind index as the Identifier changeset for consistency
    hash = Conezia.Vault.blind_index(value, "identifier_#{type}")

    Identifier
    |> where([i], i.type == ^type and i.value_hash == ^hash)
    |> preload(:entity)
    |> Repo.all()
  end

  # Tag functions

  def get_tag(id), do: Repo.get(Tag, id)

  def get_tag!(id), do: Repo.get!(Tag, id)

  def get_tag_for_user(id, user_id) do
    Tag
    |> where([t], t.id == ^id and t.user_id == ^user_id)
    |> Repo.one()
  end

  def list_tags(user_id) do
    Tag
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  def create_tag(attrs) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  def add_tags_to_entity(%Entity{} = _entity, []) do
    {:error, "No tag IDs provided"}
  end

  def add_tags_to_entity(%Entity{} = entity, tag_ids) when is_list(tag_ids) do
    now = DateTime.utc_now()

    # Convert string UUIDs to binary for raw table insert
    entity_id_binary = Ecto.UUID.dump!(entity.id)

    entries = Enum.map(tag_ids, fn tag_id ->
      %{entity_id: entity_id_binary, tag_id: Ecto.UUID.dump!(tag_id), inserted_at: now}
    end)

    Repo.insert_all("entity_tags", entries, on_conflict: :nothing)
    {:ok, Repo.preload(entity, :tags, force: true)}
  end

  def remove_tag_from_entity(%Entity{} = _entity, nil) do
    {:error, "Tag ID is required"}
  end

  def remove_tag_from_entity(%Entity{} = entity, tag_id) do
    # Convert string UUIDs to binary for raw table query
    entity_id_binary = Ecto.UUID.dump!(entity.id)
    tag_id_binary = Ecto.UUID.dump!(tag_id)

    Repo.delete_all(
      from et in "entity_tags",
        where: et.entity_id == ^entity_id_binary and et.tag_id == ^tag_id_binary
    )
    {:ok, entity}
  end

  # Group functions

  def get_group(id), do: Repo.get(Group, id)

  def get_group!(id), do: Repo.get!(Group, id)

  def get_group_for_user(id, user_id) do
    Group
    |> where([g], g.id == ^id and g.user_id == ^user_id)
    |> Repo.one()
  end

  def list_groups(user_id) do
    Group
    |> where([g], g.user_id == ^user_id)
    |> order_by([g], asc: g.name)
    |> Repo.all()
  end

  def create_group(attrs) do
    %Group{}
    |> Group.changeset(attrs)
    |> Repo.insert()
  end

  def update_group(%Group{} = group, attrs) do
    group
    |> Group.changeset(attrs)
    |> Repo.update()
  end

  def delete_group(%Group{} = group) do
    Repo.delete(group)
  end

  def add_entities_to_group(%Group{is_smart: true}, _entity_ids) do
    {:error, :cannot_add_to_smart_group}
  end

  def add_entities_to_group(%Group{} = group, entity_ids) when is_list(entity_ids) do
    now = DateTime.utc_now()

    # Convert string UUIDs to binary for raw table insert
    group_id_binary = Ecto.UUID.dump!(group.id)

    entries = Enum.map(entity_ids, fn entity_id ->
      %{
        entity_id: Ecto.UUID.dump!(entity_id),
        group_id: group_id_binary,
        added_at: now
      }
    end)

    Repo.insert_all("entity_groups", entries, on_conflict: :nothing)
    {:ok, group}
  end

  def remove_entity_from_group(%Group{is_smart: true}, _entity_id) do
    {:error, :cannot_remove_from_smart_group}
  end

  def remove_entity_from_group(%Group{} = group, entity_id) do
    # Convert string UUIDs to binary for raw table query
    group_id_binary = Ecto.UUID.dump!(group.id)
    entity_id_binary = Ecto.UUID.dump!(entity_id)

    Repo.delete_all(
      from eg in "entity_groups",
        where: eg.group_id == ^group_id_binary and eg.entity_id == ^entity_id_binary
    )
    {:ok, group}
  end

  def list_group_members(group, user_id_or_opts \\ [])

  def list_group_members(%Group{is_smart: true} = group, user_id) when is_binary(user_id) do
    entities = compute_smart_group_members(group, user_id)
    {entities, %{has_more: false, next_cursor: nil}}
  end

  def list_group_members(%Group{} = group, user_id) when is_binary(user_id) do
    # Convert string UUID to binary for raw table join
    group_id_binary = Ecto.UUID.dump!(group.id)

    entities = Entity
    |> join(:inner, [e], eg in "entity_groups", on: eg.entity_id == e.id)
    |> where([e, eg], eg.group_id == ^group_id_binary)
    |> Repo.all()

    {entities, %{has_more: false, next_cursor: nil}}
  end

  def list_group_members(%Group{} = group, opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)

    entities = if group.is_smart do
      compute_smart_group_members(group, group.user_id)
    else
      # Convert string UUID to binary for raw table join
      group_id_binary = Ecto.UUID.dump!(group.id)

      Entity
      |> join(:inner, [e], eg in "entity_groups", on: eg.entity_id == e.id)
      |> where([e, eg], eg.group_id == ^group_id_binary)
      |> limit(^limit)
      |> Repo.all()
    end

    {entities, %{has_more: length(entities) >= limit, next_cursor: nil}}
  end

  defp compute_smart_group_members(%Group{rules: rules, user_id: user_id}, _user_id) do
    query = from e in Entity, where: e.owner_id == ^user_id and is_nil(e.archived_at)

    query
    |> apply_smart_group_rules(rules)
    |> Repo.all()
  end

  defp apply_smart_group_rules(query, rules) when is_map(rules) do
    Enum.reduce(rules, query, fn
      {"type", type}, q -> where(q, [e], e.type == ^type)
      {"last_interaction_days", days}, q ->
        cutoff = DateTime.add(DateTime.utc_now(), -days * 86400, :second)
        where(q, [e], e.last_interaction_at < ^cutoff or is_nil(e.last_interaction_at))
      _, q -> q
    end)
  end

  # Extended entity functions for API

  def get_entity_for_user(id, user_id, includes) when is_list(includes) do
    Entity
    |> where([e], e.id == ^id and e.owner_id == ^user_id)
    |> preload_includes(includes)
    |> Repo.one()
  end

  defp preload_includes(query, []), do: query
  defp preload_includes(query, includes) do
    preloads = Enum.map(includes, fn
      :identifiers -> :identifiers
      :tags -> :tags
      :groups -> :groups
      :recent_interactions -> {:interactions, from(i in Conezia.Interactions.Interaction, order_by: [desc: i.occurred_at], limit: 5)}
      :relationship -> :relationship
      other -> other
    end)
    preload(query, ^preloads)
  end

  def create_entity_with_associations(attrs) do
    result = Repo.transaction(fn ->
      case create_entity(attrs) do
        {:ok, entity} ->
          # Create relationship if provided
          if rel_attrs = attrs["relationship"] do
            create_relationship(Map.merge(rel_attrs, %{
              "entity_id" => entity.id,
              "user_id" => attrs["user_id"]
            }))
          end

          # Create identifiers if provided
          if identifiers = attrs["identifiers"] do
            Enum.each(identifiers, fn id_attrs ->
              create_identifier(Map.put(id_attrs, "entity_id", entity.id))
            end)
          end

          # Add tags if provided
          if tag_ids = attrs["tag_ids"] do
            add_tags_to_entity(entity, tag_ids)
          end

          # Check for duplicates
          duplicates = find_duplicates(attrs["owner_id"], [
            name: entity.name,
            email: Enum.find_value(attrs["identifiers"] || [], fn
              %{"type" => "email", "value" => v} -> v
              _ -> nil
            end)
          ])

          {entity, Enum.filter(duplicates, & &1.id != entity.id)}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)

    case result do
      {:ok, {entity, duplicates}} -> {:ok, entity, duplicates}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def find_duplicates(nil, _opts), do: []
  def find_duplicates(user_id, opts) do
    name = Keyword.get(opts, :name)
    email = Keyword.get(opts, :email)
    phone = Keyword.get(opts, :phone)

    queries = []

    queries = if name && String.length(name) > 2 do
      q = from e in Entity,
        where: e.owner_id == ^user_id and fragment("similarity(?, ?) > 0.4", e.name, ^name),
        select: %{id: e.id, name: e.name, type: e.type, match_type: "name_similar", confidence: fragment("similarity(?, ?)", e.name, ^name)}
      [q | queries]
    else
      queries
    end

    queries = if email do
      q = from e in Entity,
        join: i in Identifier, on: i.entity_id == e.id,
        where: e.owner_id == ^user_id and i.type == "email" and i.value == ^email,
        select: %{id: e.id, name: e.name, type: e.type, match_type: "email_exact", confidence: 1.0}
      [q | queries]
    else
      queries
    end

    queries = if phone do
      q = from e in Entity,
        join: i in Identifier, on: i.entity_id == e.id,
        where: e.owner_id == ^user_id and i.type == "phone" and i.value == ^phone,
        select: %{id: e.id, name: e.name, type: e.type, match_type: "phone_exact", confidence: 1.0}
      [q | queries]
    else
      queries
    end

    queries
    |> Enum.flat_map(&Repo.all/1)
    |> Enum.uniq_by(& &1.id)
  end

  def get_relationship_for_user(id, user_id) do
    Relationship
    |> where([r], r.id == ^id and r.user_id == ^user_id)
    |> preload(:entity)
    |> Repo.one()
  end

  def get_entity_history(entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    # Combine interactions and communications into a timeline
    interactions = from(i in Conezia.Interactions.Interaction,
      where: i.entity_id == ^entity_id,
      select: %{
        event_type: "interaction",
        event_id: i.id,
        title: i.title,
        summary: i.content,
        occurred_at: i.occurred_at
      }
    )
    |> Repo.all()

    communications = from(c in Conezia.Communications.Communication,
      where: c.entity_id == ^entity_id,
      select: %{
        event_type: "communication",
        event_id: c.id,
        title: fragment("'Email: ' || coalesce(?, 'No subject')", c.subject),
        summary: fragment("left(?, 100)", c.content),
        occurred_at: c.sent_at
      }
    )
    |> Repo.all()

    events = (interactions ++ communications)
    |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
    |> Enum.take(limit)

    {events, %{has_more: false, next_cursor: nil}}
  end

  def list_identifiers(user_id, opts \\ []) do
    entity_id = Keyword.get(opts, :entity_id)
    type = Keyword.get(opts, :type)

    query = from i in Identifier,
      join: e in Entity, on: i.entity_id == e.id,
      where: e.owner_id == ^user_id

    query = if entity_id, do: where(query, [i], i.entity_id == ^entity_id), else: query
    query = if type, do: where(query, [i], i.type == ^type), else: query

    Repo.all(query)
  end

  def get_identifier_for_user(id, user_id) do
    from(i in Identifier,
      join: e in Entity, on: i.entity_id == e.id,
      where: i.id == ^id and e.owner_id == ^user_id
    )
    |> Repo.one()
  end

  def find_identifiers_by_value(user_id, type, value) do
    from(i in Identifier,
      join: e in Entity, on: i.entity_id == e.id,
      where: e.owner_id == ^user_id and i.type == ^type and i.value == ^value,
      preload: :entity
    )
    |> Repo.all()
  end

  def search_entities(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    entity_type = Keyword.get(opts, :entity_type)

    search_query = from e in Entity,
      where: e.owner_id == ^user_id,
      where: fragment("? @@ plainto_tsquery('english', ?)", e.search_vector, ^query)
             or fragment("? % ?", e.name, ^query),
      select: %{e | match_context: fragment("ts_headline('english', coalesce(?, '') || ' ' || coalesce(?, ''), plainto_tsquery('english', ?))", e.name, e.description, ^query), score: fragment("ts_rank(?, plainto_tsquery('english', ?))", e.search_vector, ^query)},
      order_by: [desc: fragment("ts_rank(?, plainto_tsquery('english', ?))", e.search_vector, ^query)],
      limit: ^limit

    search_query = if entity_type, do: where(search_query, [e], e.type == ^entity_type), else: search_query

    Repo.all(search_query)
  end

  def get_health_summary(user_id) do
    entities = from(e in Entity,
      left_join: r in Relationship, on: r.entity_id == e.id,
      where: e.owner_id == ^user_id and is_nil(e.archived_at),
      select: %{
        id: e.id,
        name: e.name,
        avatar_url: e.avatar_url,
        last_interaction_at: e.last_interaction_at,
        threshold_days: coalesce(r.health_threshold_days, 30)
      }
    )
    |> Repo.all()

    now = Date.utc_today()

    categorized = Enum.reduce(entities, %{good: 0, warning: 0, critical: 0, needs_attention: []}, fn entity, acc ->
      days_since = case entity.last_interaction_at do
        nil -> 999
        dt -> Date.diff(now, DateTime.to_date(dt))
      end

      threshold = entity.threshold_days

      cond do
        days_since <= threshold * 0.5 ->
          %{acc | good: acc.good + 1}
        days_since <= threshold ->
          %{acc | warning: acc.warning + 1}
        true ->
          attention = %{
            entity: %{id: entity.id, name: entity.name, avatar_url: entity.avatar_url},
            last_interaction_at: entity.last_interaction_at,
            days_since_interaction: days_since,
            threshold_days: threshold,
            suggested_action: "Send a quick check-in message"
          }
          %{acc | critical: acc.critical + 1, needs_attention: [attention | acc.needs_attention]}
      end
    end)

    %{
      total_entities: length(entities),
      health_breakdown: %{
        good: categorized.good,
        warning: categorized.warning,
        critical: categorized.critical
      },
      needs_attention: Enum.take(categorized.needs_attention, 10)
    }
  end

  def get_weekly_digest(user_id) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -7)

    # Count interactions this week
    interactions_count = from(i in Conezia.Interactions.Interaction,
      join: e in Entity, on: i.entity_id == e.id,
      where: e.owner_id == ^user_id,
      where: fragment("?::date >= ?", i.occurred_at, ^start_date),
      where: fragment("?::date <= ?", i.occurred_at, ^end_date)
    )
    |> Repo.aggregate(:count)

    # Count new entities this week
    new_entities = from(e in Entity,
      where: e.owner_id == ^user_id,
      where: fragment("?::date >= ?", e.inserted_at, ^start_date),
      where: fragment("?::date <= ?", e.inserted_at, ^end_date)
    )
    |> Repo.aggregate(:count)

    # Count completed reminders
    reminders_completed = from(r in Conezia.Reminders.Reminder,
      where: r.user_id == ^user_id,
      where: not is_nil(r.completed_at),
      where: fragment("?::date >= ?", r.completed_at, ^start_date),
      where: fragment("?::date <= ?", r.completed_at, ^end_date)
    )
    |> Repo.aggregate(:count)

    %{
      period: %{
        start: start_date,
        end: end_date
      },
      summary: %{
        interactions_count: interactions_count,
        new_entities: new_entities,
        reminders_completed: reminders_completed,
        relationships_improved: 0,
        relationships_declining: 0
      },
      highlights: [],
      needs_attention: []
    }
  end

  # External sync helper functions

  @doc """
  Find an entity by external ID (from external services like Google Contacts).
  Checks the legacy `external_id` field in metadata.
  """
  def find_by_external_id(user_id, external_id) do
    from(e in Entity,
      where: e.owner_id == ^user_id,
      where: fragment("? ->> 'external_id' = ?", e.metadata, ^external_id)
    )
    |> Repo.one()
  end

  @doc """
  Find an entity by external ID within the `external_ids` map in metadata.
  This searches all stored external IDs from different services.
  """
  def find_by_any_external_id(user_id, external_id) do
    # Search in the external_ids JSONB map - check if any value matches
    from(e in Entity,
      where: e.owner_id == ^user_id,
      where: fragment(
        "EXISTS (SELECT 1 FROM jsonb_each_text(COALESCE(?->'external_ids', '{}')) WHERE value = ?)",
        e.metadata,
        ^external_id
      )
    )
    |> Repo.one()
  end

  @doc """
  Find an entity by email address (case-insensitive).
  """
  def find_by_email(user_id, email) do
    normalized_email = String.downcase(email)

    from(e in Entity,
      join: i in Identifier, on: i.entity_id == e.id,
      where: e.owner_id == ^user_id and i.type == "email" and i.value == ^normalized_email
    )
    |> Repo.one()
  end

  @doc """
  Find an entity by phone number.
  """
  def find_by_phone(user_id, phone) do
    from(e in Entity,
      join: i in Identifier, on: i.entity_id == e.id,
      where: e.owner_id == ^user_id and i.type == "phone" and i.value == ^phone
    )
    |> Repo.one()
  end

  @doc """
  Find an entity by exact name match (case-insensitive).
  Used as a last resort for deduplication when no identifiers match.
  """
  def find_by_exact_name(user_id, name) do
    normalized_name = String.downcase(String.trim(name))

    from(e in Entity,
      where: e.owner_id == ^user_id and fragment("LOWER(TRIM(?)) = ?", e.name, ^normalized_name)
    )
    |> Repo.one()
  end

  @doc """
  Check if an entity has a specific identifier.
  """
  def has_identifier?(entity_id, type, value) do
    from(i in Identifier,
      where: i.entity_id == ^entity_id and i.type == ^type and i.value == ^value
    )
    |> Repo.exists?()
  end

  @doc """
  Check if an entity has any identifier of a given type.
  """
  def has_identifier_type?(entity_id, type) do
    from(i in Identifier,
      where: i.entity_id == ^entity_id and i.type == ^type
    )
    |> Repo.exists?()
  end

  # Custom Field functions

  @doc """
  Get a custom field by ID.
  """
  def get_custom_field(id), do: Repo.get(CustomField, id)

  @doc """
  Get a custom field by ID, raises if not found.
  """
  def get_custom_field!(id), do: Repo.get!(CustomField, id)

  @doc """
  List all custom fields for an entity.
  """
  def list_custom_fields(entity_id, opts \\ []) do
    category = Keyword.get(opts, :category)
    field_type = Keyword.get(opts, :field_type)

    query = from cf in CustomField,
      where: cf.entity_id == ^entity_id,
      order_by: [asc: cf.category, asc: cf.name]

    query
    |> filter_custom_field_category(category)
    |> filter_custom_field_type(field_type)
    |> Repo.all()
  end

  defp filter_custom_field_category(query, nil), do: query
  defp filter_custom_field_category(query, category), do: where(query, [cf], cf.category == ^category)

  defp filter_custom_field_type(query, nil), do: query
  defp filter_custom_field_type(query, field_type), do: where(query, [cf], cf.field_type == ^field_type)

  @doc """
  Create a custom field for an entity.
  """
  def create_custom_field(attrs) do
    %CustomField{}
    |> CustomField.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a custom field.
  """
  def update_custom_field(%CustomField{} = custom_field, attrs) do
    custom_field
    |> CustomField.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a custom field.
  """
  def delete_custom_field(%CustomField{} = custom_field) do
    Repo.delete(custom_field)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking custom field changes.
  """
  def change_custom_field(%CustomField{} = custom_field, attrs \\ %{}) do
    CustomField.changeset(custom_field, attrs)
  end

  @doc """
  Get a custom field by entity and key.
  """
  def get_custom_field_by_key(entity_id, key) do
    from(cf in CustomField,
      where: cf.entity_id == ^entity_id and cf.key == ^key
    )
    |> Repo.one()
  end

  @doc """
  Set a custom field value by key (creates or updates).
  """
  def set_custom_field(entity_id, key, value, opts \\ []) do
    case get_custom_field_by_key(entity_id, key) do
      nil ->
        attrs = %{
          entity_id: entity_id,
          key: key,
          name: Keyword.get(opts, :name, humanize_key(key)),
          field_type: Keyword.get(opts, :field_type, infer_field_type(value)),
          category: Keyword.get(opts, :category, "personal"),
          is_recurring: Keyword.get(opts, :is_recurring, false),
          reminder_days_before: Keyword.get(opts, :reminder_days_before),
          visibility: Keyword.get(opts, :visibility, "private")
        }
        |> put_typed_value(value)

        create_custom_field(attrs)

      existing ->
        attrs = put_typed_value(%{}, value)
        update_custom_field(existing, attrs)
    end
  end

  defp humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp infer_field_type(value) when is_binary(value) do
    cond do
      String.match?(value, ~r/^\d{4}-\d{2}-\d{2}$/) -> "date"
      String.match?(value, ~r/^https?:\/\//) -> "url"
      String.match?(value, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) -> "email"
      String.match?(value, ~r/^\+?[\d\s()-]+$/) -> "phone"
      true -> "text"
    end
  end
  defp infer_field_type(%Date{}), do: "date"
  defp infer_field_type(value) when is_number(value), do: "number"
  defp infer_field_type(value) when is_boolean(value), do: "boolean"
  defp infer_field_type(_), do: "text"

  defp put_typed_value(attrs, %Date{} = value), do: Map.put(attrs, :date_value, value)
  defp put_typed_value(attrs, value) when is_number(value), do: Map.put(attrs, :number_value, value)
  defp put_typed_value(attrs, value) when is_boolean(value), do: Map.put(attrs, :boolean_value, value)
  defp put_typed_value(attrs, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(attrs, :date_value, date)
      _ -> Map.put(attrs, :value, value)
    end
  end
  defp put_typed_value(attrs, nil), do: attrs

  @doc """
  Get upcoming dates for entities (e.g., birthdays, anniversaries).
  Returns custom fields with dates in the next X days.
  """
  def get_upcoming_dates(user_id, opts \\ []) do
    days_ahead = Keyword.get(opts, :days_ahead, 30)
    category = Keyword.get(opts, :category)

    today = Date.utc_today()
    end_date = Date.add(today, days_ahead)

    # For recurring dates, we need to check the month/day regardless of year
    query = from cf in CustomField,
      join: e in Entity, on: cf.entity_id == e.id,
      where: e.owner_id == ^user_id and cf.field_type == "date" and not is_nil(cf.date_value),
      select: %{
        custom_field: cf,
        entity_id: e.id,
        entity_name: e.name,
        entity_avatar_url: e.avatar_url
      },
      order_by: [asc: fragment("EXTRACT(MONTH FROM ?), EXTRACT(DAY FROM ?)", cf.date_value, cf.date_value)]

    query = if category, do: where(query, [cf], cf.category == ^category), else: query

    results = Repo.all(query)

    # Filter by upcoming dates (considering recurring dates)
    Enum.filter(results, fn %{custom_field: cf} ->
      if cf.is_recurring do
        # For recurring dates, check if the month/day falls within the range
        this_year_date = %{cf.date_value | year: today.year}
        next_year_date = %{cf.date_value | year: today.year + 1}

        (Date.compare(this_year_date, today) in [:gt, :eq] and Date.compare(this_year_date, end_date) in [:lt, :eq]) or
        (Date.compare(next_year_date, today) in [:gt, :eq] and Date.compare(next_year_date, end_date) in [:lt, :eq])
      else
        Date.compare(cf.date_value, today) in [:gt, :eq] and Date.compare(cf.date_value, end_date) in [:lt, :eq]
      end
    end)
  end

  @doc """
  Get all custom fields of a specific category for a user's entities.
  """
  def list_custom_fields_by_category(user_id, category) do
    from(cf in CustomField,
      join: e in Entity, on: cf.entity_id == e.id,
      where: e.owner_id == ^user_id and cf.category == ^category,
      preload: [entity: e],
      order_by: [asc: cf.name]
    )
    |> Repo.all()
  end

  @doc """
  Get predefined field suggestions.
  """
  def predefined_custom_fields do
    CustomField.predefined_fields()
  end

  # Entity Relationship functions (connection-to-connection relationships)

  @doc """
  Get an entity relationship by ID.
  """
  def get_entity_relationship(id), do: Repo.get(EntityRelationship, id)

  @doc """
  Get an entity relationship by ID, raises if not found.
  """
  def get_entity_relationship!(id), do: Repo.get!(EntityRelationship, id)

  @doc """
  Get an entity relationship for a user by ID.
  """
  def get_entity_relationship_for_user(id, user_id) do
    from(er in EntityRelationship,
      where: er.id == ^id and er.user_id == ^user_id,
      preload: [:source_entity, :target_entity]
    )
    |> Repo.one()
  end

  @doc """
  List all entity relationships for a user.
  """
  def list_entity_relationships(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    type = Keyword.get(opts, :type)

    query = from er in EntityRelationship,
      where: er.user_id == ^user_id,
      limit: ^limit,
      preload: [:source_entity, :target_entity],
      order_by: [desc: er.inserted_at]

    query
    |> filter_entity_relationship_type(type)
    |> Repo.all()
  end

  defp filter_entity_relationship_type(query, nil), do: query
  defp filter_entity_relationship_type(query, type), do: where(query, [er], er.type == ^type)

  @doc """
  List all entity relationships for a specific entity.
  Returns relationships where the entity is either the source or target.
  """
  def list_entity_relationships_for_entity(entity_id, user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(er in EntityRelationship,
      where: er.user_id == ^user_id and (er.source_entity_id == ^entity_id or er.target_entity_id == ^entity_id),
      limit: ^limit,
      preload: [:source_entity, :target_entity],
      order_by: [desc: er.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get a specific entity relationship between two entities.
  Checks both directions since A->B and B->A represent the same relationship.
  """
  def get_entity_relationship_between(user_id, entity_id_1, entity_id_2) do
    from(er in EntityRelationship,
      where: er.user_id == ^user_id and
             ((er.source_entity_id == ^entity_id_1 and er.target_entity_id == ^entity_id_2) or
              (er.source_entity_id == ^entity_id_2 and er.target_entity_id == ^entity_id_1)),
      preload: [:source_entity, :target_entity]
    )
    |> Repo.one()
  end

  @doc """
  Create an entity relationship.
  """
  def create_entity_relationship(attrs) do
    %EntityRelationship{}
    |> EntityRelationship.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an entity relationship.
  """
  def update_entity_relationship(%EntityRelationship{} = entity_relationship, attrs) do
    entity_relationship
    |> EntityRelationship.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete an entity relationship.
  """
  def delete_entity_relationship(%EntityRelationship{} = entity_relationship) do
    Repo.delete(entity_relationship)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking entity relationship changes.
  """
  def change_entity_relationship(%EntityRelationship{} = entity_relationship, attrs \\ %{}) do
    EntityRelationship.changeset(entity_relationship, attrs)
  end

  @doc """
  Get entity relationships grouped by entity for display.
  Returns a map of entity_id => list of {other_entity, relationship, label}
  """
  def get_entity_relationship_map(user_id, entity_ids) when is_list(entity_ids) do
    relationships = from(er in EntityRelationship,
      where: er.user_id == ^user_id and
             (er.source_entity_id in ^entity_ids or er.target_entity_id in ^entity_ids),
      preload: [:source_entity, :target_entity]
    )
    |> Repo.all()

    # Build a map of entity_id => list of related entities with their relationship info
    Enum.reduce(relationships, %{}, fn rel, acc ->
      # For each relationship, add entries for both entities involved
      acc
      |> add_relationship_entry(rel.source_entity_id, rel.target_entity, EntityRelationship.display_label_for_source(rel), rel)
      |> add_relationship_entry(rel.target_entity_id, rel.source_entity, EntityRelationship.display_label_for_target(rel), rel)
    end)
  end

  defp add_relationship_entry(acc, entity_id, other_entity, label, relationship) do
    entry = %{other_entity: other_entity, label: label, relationship: relationship}
    Map.update(acc, entity_id, [entry], fn existing -> [entry | existing] end)
  end

  # ============================================================================
  # Deduplication Functions
  # ============================================================================

  @doc """
  Find all duplicate entity groups for a user.

  Returns a list of duplicate groups, where each group contains entities that
  are likely duplicates of each other based on:
  - Exact email match
  - Exact phone match
  - Similar names (>0.6 similarity threshold)

  Each group has a primary entity (the one to keep) and duplicate entities.
  """
  def find_all_duplicates(user_id) do
    # Get all entities with their identifiers
    entities =
      from(e in Entity,
        where: e.owner_id == ^user_id and is_nil(e.archived_at),
        preload: [:identifiers],
        order_by: [asc: e.inserted_at]
      )
      |> Repo.all()

    # Build lookup maps for matching
    email_map = build_identifier_map(entities, "email")
    phone_map = build_identifier_map(entities, "phone")

    # Find duplicate groups
    find_duplicate_groups(entities, email_map, phone_map)
  end

  defp build_identifier_map(entities, type) do
    Enum.reduce(entities, %{}, fn entity, acc ->
      entity.identifiers
      |> Enum.filter(&(&1.type == type && &1.value))
      |> Enum.reduce(acc, fn identifier, inner_acc ->
        key = String.downcase(identifier.value)
        Map.update(inner_acc, key, [entity.id], &[entity.id | &1])
      end)
    end)
  end

  defp find_duplicate_groups(entities, email_map, phone_map) do
    # Track which entities we've already grouped
    processed = MapSet.new()

    {groups, _} =
      Enum.reduce(entities, {[], processed}, fn entity, {groups, seen} ->
        if MapSet.member?(seen, entity.id) do
          {groups, seen}
        else
          # Find all entities that match this one
          matching_ids = find_matching_entity_ids(entity, email_map, phone_map, entities)

          if length(matching_ids) > 1 do
            # Sort by inserted_at to pick the oldest as primary
            sorted_ids = Enum.sort_by(matching_ids, fn id ->
              Enum.find(entities, &(&1.id == id)).inserted_at
            end)

            [primary_id | duplicate_ids] = sorted_ids
            primary = Enum.find(entities, &(&1.id == primary_id))
            duplicates = Enum.filter(entities, &(&1.id in duplicate_ids))

            group = %{
              primary: primary,
              duplicates: duplicates,
              match_reasons: get_match_reasons(primary, duplicates, email_map, phone_map)
            }

            new_seen = Enum.reduce(matching_ids, seen, &MapSet.put(&2, &1))
            {[group | groups], new_seen}
          else
            {groups, MapSet.put(seen, entity.id)}
          end
        end
      end)

    Enum.reverse(groups)
  end

  defp find_matching_entity_ids(entity, email_map, phone_map, all_entities) do
    # Get IDs matching by email
    email_matches =
      entity.identifiers
      |> Enum.filter(&(&1.type == "email" && &1.value))
      |> Enum.flat_map(fn id ->
        Map.get(email_map, String.downcase(id.value), [])
      end)

    # Get IDs matching by phone
    phone_matches =
      entity.identifiers
      |> Enum.filter(&(&1.type == "phone" && &1.value))
      |> Enum.flat_map(fn id ->
        Map.get(phone_map, String.downcase(id.value), [])
      end)

    # Get IDs matching by similar name (>0.6 similarity)
    name_matches =
      all_entities
      |> Enum.filter(fn other ->
        other.id != entity.id &&
        name_similarity(entity.name, other.name) > 0.6
      end)
      |> Enum.map(& &1.id)

    # Combine all matches and include self
    ([entity.id] ++ email_matches ++ phone_matches ++ name_matches)
    |> Enum.uniq()
  end

  defp name_similarity(name1, name2) when is_binary(name1) and is_binary(name2) do
    # Use Jaro-Winkler similarity for names
    n1 = String.downcase(String.trim(name1))
    n2 = String.downcase(String.trim(name2))

    if n1 == n2 do
      1.0
    else
      # Simple Jaccard similarity on words
      words1 = String.split(n1) |> MapSet.new()
      words2 = String.split(n2) |> MapSet.new()

      intersection = MapSet.intersection(words1, words2) |> MapSet.size()
      union = MapSet.union(words1, words2) |> MapSet.size()

      if union > 0, do: intersection / union, else: 0.0
    end
  end
  defp name_similarity(_, _), do: 0.0

  defp get_match_reasons(primary, duplicates, _email_map, _phone_map) do
    Enum.flat_map(duplicates, fn dup ->
      reasons = []

      # Check email matches
      primary_emails = get_identifier_values(primary, "email")
      dup_emails = get_identifier_values(dup, "email")
      common_emails = MapSet.intersection(primary_emails, dup_emails)

      reasons = if MapSet.size(common_emails) > 0 do
        ["email: #{Enum.join(common_emails, ", ")}" | reasons]
      else
        reasons
      end

      # Check phone matches
      primary_phones = get_identifier_values(primary, "phone")
      dup_phones = get_identifier_values(dup, "phone")
      common_phones = MapSet.intersection(primary_phones, dup_phones)

      reasons = if MapSet.size(common_phones) > 0 do
        ["phone: #{Enum.join(common_phones, ", ")}" | reasons]
      else
        reasons
      end

      # Check name similarity
      similarity = name_similarity(primary.name, dup.name)
      if similarity > 0.6 do
        ["name similarity: #{Float.round(similarity * 100, 1)}%" | reasons]
      else
        reasons
      end
    end)
    |> Enum.uniq()
  end

  defp get_identifier_values(entity, type) do
    entity.identifiers
    |> Enum.filter(&(&1.type == type && &1.value))
    |> Enum.map(&String.downcase(&1.value))
    |> MapSet.new()
  end

  @doc """
  Merge multiple duplicate entities into a primary entity.

  This will:
  1. Move all identifiers from duplicates to primary (avoiding duplicates)
  2. Move all relationships from duplicates to primary
  3. Move all interactions from duplicates to primary
  4. Move all custom fields from duplicates to primary
  5. Update primary's metadata with merged external_ids
  6. Delete the duplicate entities
  """
  def merge_duplicate_entities(primary_id, duplicate_ids, user_id) when is_list(duplicate_ids) do
    Repo.transaction(fn ->
      # Verify all entities belong to the user
      primary = get_entity_for_user(primary_id, user_id)
      duplicates = Enum.map(duplicate_ids, &get_entity_for_user(&1, user_id))

      if is_nil(primary) or Enum.any?(duplicates, &is_nil/1) do
        Repo.rollback(:entity_not_found)
      end

      # Load primary with associations
      primary = Repo.preload(primary, [:identifiers, :relationships, :custom_fields])

      # Merge each duplicate into primary
      Enum.each(duplicates, fn dup ->
        dup = Repo.preload(dup, [:identifiers, :relationships, :custom_fields])
        merge_single_entity(primary, dup)
      end)

      # Update primary's metadata with merged info
      merged_count = length(duplicate_ids)
      primary_metadata = primary.metadata || %{}

      # Consolidate all external_ids from duplicates
      all_external_ids =
        [primary | duplicates]
        |> Enum.reduce(%{}, fn entity, acc ->
          entity_metadata = entity.metadata || %{}
          # Get external_ids map
          ext_ids = entity_metadata["external_ids"] || %{}
          # Also check legacy external_id field
          ext_ids = case entity_metadata["external_id"] do
            nil -> ext_ids
            ext_id ->
              source = entity_metadata["source"] || "unknown"
              Map.put_new(ext_ids, source, ext_id)
          end
          Map.merge(acc, ext_ids)
        end)

      # Consolidate all sources from duplicates
      all_sources =
        [primary | duplicates]
        |> Enum.flat_map(fn entity ->
          entity_metadata = entity.metadata || %{}
          entity_metadata["sources"] || [entity_metadata["source"]]
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      metadata = primary_metadata
        |> Map.put("merged_count", (primary_metadata["merged_count"] || 0) + merged_count)
        |> Map.put("last_merged_at", DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put("external_ids", all_external_ids)
        |> Map.put("sources", all_sources)

      {:ok, updated_primary} = update_entity(primary, %{metadata: metadata})

      # Delete duplicates
      Enum.each(duplicate_ids, fn dup_id ->
        from(e in Entity, where: e.id == ^dup_id)
        |> Repo.delete_all()
      end)

      updated_primary
    end)
  end

  defp merge_single_entity(primary, duplicate) do
    # Move identifiers (avoiding duplicates)
    Enum.each(duplicate.identifiers, fn identifier ->
      unless has_identifier?(primary.id, identifier.type, identifier.value) do
        from(i in Identifier, where: i.id == ^identifier.id)
        |> Repo.update_all(set: [
          entity_id: primary.id,
          is_primary: false,  # New identifiers are not primary
          updated_at: DateTime.utc_now()
        ])
      else
        # Delete duplicate identifier
        Repo.delete(identifier)
      end
    end)

    # Move relationships
    from(r in Relationship, where: r.entity_id == ^duplicate.id)
    |> Repo.update_all(set: [entity_id: primary.id, updated_at: DateTime.utc_now()])

    # Move entity-to-entity relationships
    from(r in EntityRelationship, where: r.source_entity_id == ^duplicate.id)
    |> Repo.update_all(set: [source_entity_id: primary.id, updated_at: DateTime.utc_now()])

    from(r in EntityRelationship, where: r.target_entity_id == ^duplicate.id)
    |> Repo.update_all(set: [target_entity_id: primary.id, updated_at: DateTime.utc_now()])

    # Move interactions
    from(i in Conezia.Interactions.Interaction, where: i.entity_id == ^duplicate.id)
    |> Repo.update_all(set: [entity_id: primary.id, updated_at: DateTime.utc_now()])

    # Move conversations
    from(c in Conezia.Communications.Conversation, where: c.entity_id == ^duplicate.id)
    |> Repo.update_all(set: [entity_id: primary.id, updated_at: DateTime.utc_now()])

    # Move reminders
    from(r in Conezia.Reminders.Reminder, where: r.entity_id == ^duplicate.id)
    |> Repo.update_all(set: [entity_id: primary.id, updated_at: DateTime.utc_now()])

    # Move custom fields (avoiding duplicates by name)
    existing_field_names =
      primary.custom_fields
      |> Enum.map(&{&1.name, &1.category})
      |> MapSet.new()

    Enum.each(duplicate.custom_fields, fn field ->
      if MapSet.member?(existing_field_names, {field.name, field.category}) do
        Repo.delete(field)
      else
        from(cf in CustomField, where: cf.id == ^field.id)
        |> Repo.update_all(set: [entity_id: primary.id, updated_at: DateTime.utc_now()])
      end
    end)

    # Move tags - use type annotation for binary_id
    dup_id = Ecto.UUID.dump!(duplicate.id)
    Repo.query!("DELETE FROM entity_tags WHERE entity_id = $1", [dup_id])

    # Note: We don't copy tags as they might create duplicates

    # Move group memberships
    Repo.query!("DELETE FROM entity_groups WHERE entity_id = $1", [dup_id])

    # Merge description if primary doesn't have one
    if is_nil(primary.description) && duplicate.description do
      update_entity(primary, %{description: duplicate.description})
    end

    # Merge avatar if primary doesn't have one
    if is_nil(primary.avatar_url) && duplicate.avatar_url do
      update_entity(primary, %{avatar_url: duplicate.avatar_url})
    end

    # Merge last_interaction_at (keep the most recent)
    if duplicate.last_interaction_at do
      if is_nil(primary.last_interaction_at) ||
         DateTime.compare(duplicate.last_interaction_at, primary.last_interaction_at) == :gt do
        update_entity(primary, %{last_interaction_at: duplicate.last_interaction_at})
      end
    end
  end

  @doc """
  Automatically merge all duplicate groups for a user.

  Returns {:ok, merged_count} or {:error, reason}.
  """
  def auto_merge_duplicates(user_id) do
    groups = find_all_duplicates(user_id)

    results =
      Enum.map(groups, fn group ->
        duplicate_ids = Enum.map(group.duplicates, & &1.id)
        merge_duplicate_entities(group.primary.id, duplicate_ids, user_id)
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    {:ok, %{merged_groups: successful, failed_groups: failed, total_duplicates_removed: Enum.sum(Enum.map(groups, &length(&1.duplicates)))}}
  end

end
