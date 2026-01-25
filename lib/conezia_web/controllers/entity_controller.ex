defmodule ConeziaWeb.EntityController do
  @moduledoc """
  Controller for entity management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/entities
  List all entities for the current user.
  """
  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      type: params["type"],
      tag: params["tag"],
      tags: params["tags[]"] || params["tags"],
      status: params["status"] || "active",
      q: params["q"],
      sort: params["sort"] || "name",
      order: params["order"] || "asc",
      limit: parse_int(params["limit"], 50, 100),
      cursor: params["cursor"]
    ]

    {entities, meta} = Entities.list_entities(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(entities, &entity_list_json/1),
      meta: meta
    })
  end

  @doc """
  GET /api/v1/entities/:id
  Get a single entity.
  """
  def show(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    includes = parse_includes(params["include"])

    case Entities.get_entity_for_user(id, user.id, includes) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        conn
        |> put_status(:ok)
        |> json(%{data: entity_detail_json(entity, includes)})
    end
  end

  @doc """
  POST /api/v1/entities
  Create a new entity.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    attrs = Map.put(params, "owner_id", user.id)

    case Entities.create_entity_with_associations(attrs) do
      {:ok, entity, potential_duplicates} ->
        response = %{data: entity_detail_json(entity, [])}

        response =
          if length(potential_duplicates) > 0 do
            Map.put(response, :meta, %{potential_duplicates: potential_duplicates})
          else
            response
          end

        conn
        |> put_status(:created)
        |> json(response)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  PUT /api/v1/entities/:id
  Update an entity.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        case Entities.update_entity(entity, params) do
          {:ok, updated_entity} ->
            conn
            |> put_status(:ok)
            |> json(%{data: entity_detail_json(updated_entity, [])})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/entities/:id
  Delete or archive an entity.
  """
  def delete(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    permanent = params["permanent"] == "true"

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        result =
          if permanent do
            Entities.delete_entity(entity)
          else
            Entities.archive_entity(entity)
          end

        case result do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: if(permanent, do: "Entity deleted", else: "Entity archived")}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/entities/:id/archive
  Archive an entity.
  """
  def archive(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        case Entities.archive_entity(entity) do
          {:ok, archived_entity} ->
            conn
            |> put_status(:ok)
            |> json(%{data: entity_detail_json(archived_entity, [])})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/entities/:id/unarchive
  Unarchive an entity.
  """
  def unarchive(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        case Entities.unarchive_entity(entity) do
          {:ok, unarchived_entity} ->
            conn
            |> put_status(:ok)
            |> json(%{data: entity_detail_json(unarchived_entity, [])})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/entities/merge
  Merge two entities.
  """
  def merge(conn, %{"source_id" => source_id, "target_id" => target_id} = params) do
    user = Guardian.Plug.current_resource(conn)

    with {:source, source} when not is_nil(source) <- {:source, Entities.get_entity_for_user(source_id, user.id)},
         {:target, target} when not is_nil(target) <- {:target, Entities.get_entity_for_user(target_id, user.id)},
         {:same, false} <- {:same, source_id == target_id},
         {:type_match, true} <- {:type_match, source.type == target.type} do
      options = params["options"] || %{}

      case Entities.merge_entities(source, target, options) do
        {:ok, merged_entity, summary} ->
          conn
          |> put_status(:ok)
          |> json(%{
            data: Map.merge(entity_detail_json(merged_entity, []), %{
              merged_at: DateTime.utc_now(),
              merge_summary: summary
            }),
            meta: %{message: "Entities merged successfully"}
          })

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(ErrorHelpers.bad_request(reason, conn.request_path))
      end
    else
      {:source, nil} ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("source entity", source_id, conn.request_path))

      {:target, nil} ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("target entity", target_id, conn.request_path))

      {:same, true} ->
        conn
        |> put_status(:conflict)
        |> json(ErrorHelpers.conflict("Cannot merge an entity with itself.", conn.request_path))

      {:type_match, false} ->
        conn
        |> put_status(:conflict)
        |> json(ErrorHelpers.conflict(
          "Cannot merge entities of different types.",
          conn.request_path
        ))
    end
  end

  def merge(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ErrorHelpers.error_response(
      :validation_error, "Validation Error", 422, "Invalid merge request.",
      instance: conn.request_path,
      errors: [
        %{field: "source_id", code: "required", message: "is required"},
        %{field: "target_id", code: "required", message: "is required"}
      ]
    ))
  end

  @doc """
  GET /api/v1/entities/duplicates
  Check for duplicate entities.
  """
  def check_duplicates(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      name: params["name"],
      email: params["email"],
      phone: params["phone"]
    ]

    matches = Entities.find_duplicates(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: %{
        has_duplicates: length(matches) > 0,
        matches: matches
      }
    })
  end

  @doc """
  GET /api/v1/entities/:id/interactions
  List interactions for an entity.
  """
  def list_interactions(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      _entity ->
        opts = [
          limit: parse_int(params["limit"], 50, 100),
          cursor: params["cursor"]
        ]

        {interactions, meta} = Conezia.Interactions.list_interactions_for_entity(id, user.id, opts)

        conn
        |> put_status(:ok)
        |> json(%{
          data: Enum.map(interactions, &interaction_json/1),
          meta: meta
        })
    end
  end

  @doc """
  GET /api/v1/entities/:id/history
  Get the timeline/history for an entity.
  """
  def history(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      _entity ->
        opts = [
          types: params["types"],
          limit: parse_int(params["limit"], 50, 100),
          cursor: params["cursor"]
        ]

        {events, meta} = Entities.get_entity_history(id, opts)

        conn
        |> put_status(:ok)
        |> json(%{data: events, meta: meta})
    end
  end

  @doc """
  GET /api/v1/entities/:id/conversations
  List conversations for an entity.
  """
  def list_conversations(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      _entity ->
        opts = [
          limit: parse_int(params["limit"], 50, 100),
          cursor: params["cursor"]
        ]

        {conversations, meta} = Conezia.Communications.list_conversations_for_entity(id, user.id, opts)

        conn
        |> put_status(:ok)
        |> json(%{
          data: Enum.map(conversations, &conversation_list_json/1),
          meta: meta
        })
    end
  end

  @doc """
  GET /api/v1/entities/:id/reminders
  List reminders for an entity.
  """
  def list_reminders(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      _entity ->
        opts = [
          limit: parse_int(params["limit"], 50, 100),
          cursor: params["cursor"]
        ]

        {reminders, meta} = Conezia.Reminders.list_reminders_for_entity(id, user.id, opts)

        conn
        |> put_status(:ok)
        |> json(%{
          data: Enum.map(reminders, &reminder_json/1),
          meta: meta
        })
    end
  end

  @doc """
  GET /api/v1/entities/:id/attachments
  List attachments for an entity.
  """
  def list_attachments(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      _entity ->
        opts = [
          limit: parse_int(params["limit"], 50, 100),
          cursor: params["cursor"]
        ]

        {attachments, meta} = Conezia.Attachments.list_attachments_for_entity(id, user.id, opts)

        conn
        |> put_status(:ok)
        |> json(%{
          data: Enum.map(attachments, &attachment_json/1),
          meta: meta
        })
    end
  end

  @doc """
  GET /api/v1/entities/:id/identifiers
  List identifiers for an entity.
  """
  def list_identifiers(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id, [:identifiers]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        conn
        |> put_status(:ok)
        |> json(%{data: Enum.map(entity.identifiers, &identifier_json/1)})
    end
  end

  @doc """
  POST /api/v1/entities/:id/identifiers
  Add an identifier to an entity.
  """
  def create_identifier(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      _entity ->
        attrs = Map.put(params, "entity_id", id)

        case Entities.create_identifier(attrs) do
          {:ok, identifier} ->
            conn
            |> put_status(:created)
            |> json(%{data: identifier_json(identifier)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/entities/:id/tags
  Add tags to an entity.
  """
  def add_tags(conn, %{"id" => id, "tag_ids" => tag_ids}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        case Entities.add_tags_to_entity(entity, tag_ids) do
          {:ok, updated_entity} ->
            conn
            |> put_status(:ok)
            |> json(%{data: %{tags: Enum.map(updated_entity.tags, &tag_json/1)}})

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))
        end
    end
  end

  def add_tags(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("tag_ids is required.", conn.request_path))
  end

  @doc """
  DELETE /api/v1/entities/:id/tags/:tag_id
  Remove a tag from an entity.
  """
  def remove_tag(conn, %{"id" => id, "tag_id" => tag_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        case Entities.remove_tag_from_entity(entity, tag_id) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Tag removed"}})

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))
        end
    end
  end

  @doc """
  GET /api/v1/entities/:id/activity
  Get activity log for an entity.
  """
  def activity(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      _entity ->
        opts = [
          limit: parse_int(params["limit"], 50, 100),
          cursor: params["cursor"]
        ]

        {activities, meta} = Conezia.Interactions.list_activity_for_entity(id, opts)

        conn
        |> put_status(:ok)
        |> json(%{
          data: Enum.map(activities, &activity_json/1),
          meta: meta
        })
    end
  end

  @doc """
  PUT /api/v1/entities/:id/health-threshold
  Set health threshold for an entity's relationship.
  """
  def set_health_threshold(conn, %{"id" => id, "threshold_days" => threshold_days}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_entity_for_user(id, user.id, [:relationship]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", id, conn.request_path))

      entity ->
        case Entities.update_relationship(entity.relationship, %{health_threshold_days: threshold_days}) do
          {:ok, relationship} ->
            conn
            |> put_status(:ok)
            |> json(%{data: %{threshold_days: relationship.health_threshold_days}})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  def set_health_threshold(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("threshold_days is required.", conn.request_path))
  end

  # Private helpers

  defp parse_int(nil, default, _max), do: default
  defp parse_int(val, default, max) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> min(num, max)
      :error -> default
    end
  end
  defp parse_int(val, _default, max) when is_integer(val), do: min(val, max)
  defp parse_int(_, default, _max), do: default

  defp parse_includes(nil), do: []
  defp parse_includes(includes) when is_binary(includes) do
    includes
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
    |> Enum.filter(&(&1 in [:identifiers, :tags, :groups, :recent_interactions]))
  end

  defp entity_list_json(entity) do
    # Get relationship from the user's relationship to this entity, if loaded
    relationship = get_entity_relationship(entity)

    %{
      id: entity.id,
      type: entity.type,
      name: entity.name,
      description: entity.description,
      avatar_url: entity.avatar_url,
      last_interaction_at: entity.last_interaction_at,
      relationship: relationship_summary_json(relationship),
      tags: Enum.map(get_loaded_or_empty(entity, :tags), &tag_json/1),
      primary_identifiers: primary_identifiers(get_loaded_or_empty(entity, :identifiers)),
      inserted_at: entity.inserted_at,
      updated_at: entity.updated_at
    }
  end

  defp get_entity_relationship(entity) do
    case Map.get(entity, :relationship) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      relationship -> relationship
    end
  end

  defp get_loaded_or_empty(entity, field) do
    case Map.get(entity, field) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      value -> value
    end
  end

  defp entity_detail_json(entity, includes) do
    relationship = get_entity_relationship(entity)

    base = %{
      id: entity.id,
      type: entity.type,
      name: entity.name,
      description: entity.description,
      avatar_url: entity.avatar_url,
      metadata: entity.metadata,
      last_interaction_at: entity.last_interaction_at,
      archived_at: entity.archived_at,
      relationship: relationship_json(relationship),
      inserted_at: entity.inserted_at,
      updated_at: entity.updated_at
    }

    identifiers = get_loaded_or_empty(entity, :identifiers)
    base = if :identifiers in includes or identifiers != [] do
      Map.put(base, :identifiers, Enum.map(identifiers, &identifier_json/1))
    else
      base
    end

    tags = get_loaded_or_empty(entity, :tags)
    base = if :tags in includes or tags != [] do
      Map.put(base, :tags, Enum.map(tags, &tag_json/1))
    else
      base
    end

    groups = get_loaded_or_empty(entity, :groups)
    base = if :groups in includes and groups != [] do
      Map.put(base, :groups, Enum.map(groups, &group_summary_json/1))
    else
      base
    end

    if :recent_interactions in includes and entity.recent_interactions do
      Map.put(base, :recent_interactions, Enum.map(entity.recent_interactions, &interaction_summary_json/1))
    else
      base
    end
  end

  defp relationship_json(nil), do: nil
  defp relationship_json(relationship) do
    %{
      id: relationship.id,
      type: relationship.type,
      strength: relationship.strength,
      status: relationship.status,
      started_at: relationship.started_at,
      health_threshold_days: relationship.health_threshold_days,
      notes: relationship.notes
    }
  end

  defp relationship_summary_json(nil), do: nil
  defp relationship_summary_json(relationship) do
    %{
      id: relationship.id,
      type: relationship.type,
      strength: relationship.strength,
      status: relationship.status,
      health_score: calculate_health_score(relationship)
    }
  end

  defp calculate_health_score(relationship) do
    # Simple health calculation based on last interaction
    # TODO: Implement more sophisticated health calculation
    case relationship.last_interaction_at do
      nil -> "warning"
      last_at ->
        days_since = Date.diff(Date.utc_today(), DateTime.to_date(last_at))
        threshold = relationship.health_threshold_days || 30

        cond do
          days_since <= threshold * 0.5 -> "good"
          days_since <= threshold -> "warning"
          true -> "critical"
        end
    end
  end

  defp tag_json(tag) do
    %{
      id: tag.id,
      name: tag.name,
      color: tag.color
    }
  end

  defp group_summary_json(group) do
    %{
      id: group.id,
      name: group.name
    }
  end

  defp identifier_json(identifier) do
    %{
      id: identifier.id,
      type: identifier.type,
      value: identifier.value,
      label: identifier.label,
      is_primary: identifier.is_primary,
      verified_at: identifier.verified_at
    }
  end

  defp primary_identifiers(identifiers) do
    identifiers
    |> Enum.filter(& &1.is_primary)
    |> Enum.reduce(%{}, fn id, acc ->
      Map.put(acc, id.type, id.value)
    end)
  end

  defp interaction_json(interaction) do
    %{
      id: interaction.id,
      type: interaction.type,
      title: interaction.title,
      content: interaction.content,
      occurred_at: interaction.occurred_at,
      entity: entity_summary_json(interaction.entity),
      attachments: Enum.map(interaction.attachments || [], &attachment_json/1),
      inserted_at: interaction.inserted_at
    }
  end

  defp interaction_summary_json(interaction) do
    %{
      id: interaction.id,
      type: interaction.type,
      title: interaction.title,
      occurred_at: interaction.occurred_at
    }
  end

  defp entity_summary_json(nil), do: nil
  defp entity_summary_json(entity) do
    %{
      id: entity.id,
      name: entity.name,
      avatar_url: entity.avatar_url
    }
  end

  defp conversation_list_json(conversation) do
    %{
      id: conversation.id,
      entity: entity_summary_json(conversation.entity),
      channel: conversation.channel,
      subject: conversation.subject,
      last_message_at: conversation.last_message_at,
      last_message_preview: conversation.last_message_preview,
      unread_count: conversation.unread_count,
      is_archived: conversation.archived_at != nil
    }
  end

  defp reminder_json(reminder) do
    %{
      id: reminder.id,
      type: reminder.type,
      title: reminder.title,
      description: reminder.description,
      due_at: reminder.due_at,
      entity: entity_summary_json(reminder.entity),
      recurrence_rule: reminder.recurrence_rule,
      notification_channels: reminder.notification_channels,
      status: reminder_status(reminder),
      snoozed_until: reminder.snoozed_until,
      completed_at: reminder.completed_at
    }
  end

  defp reminder_status(reminder) do
    cond do
      reminder.completed_at -> "completed"
      reminder.snoozed_until && DateTime.compare(reminder.snoozed_until, DateTime.utc_now()) == :gt -> "snoozed"
      DateTime.compare(reminder.due_at, DateTime.utc_now()) == :lt -> "overdue"
      true -> "pending"
    end
  end

  defp attachment_json(attachment) do
    %{
      id: attachment.id,
      filename: attachment.filename,
      mime_type: attachment.mime_type,
      size_bytes: attachment.size_bytes,
      download_url: attachment.storage_path,
      inserted_at: attachment.inserted_at
    }
  end

  defp activity_json(activity) do
    %{
      id: activity.id,
      action: activity.action,
      resource_type: activity.resource_type,
      resource_id: activity.resource_id,
      resource_name: activity.metadata["resource_name"],
      metadata: activity.metadata,
      inserted_at: activity.inserted_at
    }
  end
end
