defmodule Conezia.Entities do
  @moduledoc """
  The Entities context for managing contacts/entities and their relationships.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Entities.{Entity, Relationship, Identifier, Tag, Group}

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
      limit: ^limit,
      offset: ^offset,
      order_by: [desc: e.last_interaction_at, desc: e.inserted_at]

    query
    |> filter_by_type(type)
    |> filter_by_status(status)
    |> filter_by_search(search)
    |> Repo.all()
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

    Enum.each(new_tag_ids, fn tag_id ->
      Repo.insert_all("entity_tags", [
        %{entity_id: target.id, tag_id: tag_id, inserted_at: DateTime.utc_now()}
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
    hash = :crypto.hash(:sha256, String.downcase(value)) |> Base.encode16(case: :lower)

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

    entries = Enum.map(tag_ids, fn tag_id ->
      %{entity_id: entity.id, tag_id: tag_id, inserted_at: now}
    end)

    Repo.insert_all("entity_tags", entries, on_conflict: :nothing)
    {:ok, Repo.preload(entity, :tags, force: true)}
  end

  def remove_tag_from_entity(%Entity{} = _entity, nil) do
    {:error, "Tag ID is required"}
  end

  def remove_tag_from_entity(%Entity{} = entity, tag_id) do
    Repo.delete_all(
      from et in "entity_tags",
        where: et.entity_id == ^entity.id and et.tag_id == ^tag_id
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

    entries = Enum.map(entity_ids, fn entity_id ->
      %{entity_id: entity_id, group_id: group.id, added_at: now}
    end)

    Repo.insert_all("entity_groups", entries, on_conflict: :nothing)
    {:ok, group}
  end

  def remove_entity_from_group(%Group{is_smart: true}, _entity_id) do
    {:error, :cannot_remove_from_smart_group}
  end

  def remove_entity_from_group(%Group{} = group, entity_id) do
    Repo.delete_all(
      from eg in "entity_groups",
        where: eg.group_id == ^group.id and eg.entity_id == ^entity_id
    )
    {:ok, group}
  end

  def list_group_members(group, user_id_or_opts \\ [])

  def list_group_members(%Group{is_smart: true} = group, user_id) when is_binary(user_id) do
    entities = compute_smart_group_members(group, user_id)
    {entities, %{has_more: false, next_cursor: nil}}
  end

  def list_group_members(%Group{} = group, user_id) when is_binary(user_id) do
    entities = Entity
    |> join(:inner, [e], eg in "entity_groups", on: eg.entity_id == e.id)
    |> where([e, eg], eg.group_id == ^group.id)
    |> Repo.all()

    {entities, %{has_more: false, next_cursor: nil}}
  end

  def list_group_members(%Group{} = group, opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)

    entities = if group.is_smart do
      compute_smart_group_members(group, group.user_id)
    else
      Entity
      |> join(:inner, [e], eg in "entity_groups", on: eg.entity_id == e.id)
      |> where([e, eg], eg.group_id == ^group.id)
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
          duplicates = find_duplicates(attrs["user_id"], [
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

end
