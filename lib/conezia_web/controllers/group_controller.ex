defmodule ConeziaWeb.GroupController do
  @moduledoc """
  Controller for group management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/groups
  List all groups for the current user.
  """
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    groups = Entities.list_groups(user.id)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(groups, &group_list_json/1)})
  end

  @doc """
  GET /api/v1/groups/:id
  Get a single group.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_group_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("group", id, conn.request_path))

      group ->
        conn
        |> put_status(:ok)
        |> json(%{data: group_detail_json(group)})
    end
  end

  @doc """
  POST /api/v1/groups
  Create a new group.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    attrs = Map.put(params, "user_id", user.id)

    case Entities.create_group(attrs) do
      {:ok, group} ->
        conn
        |> put_status(:created)
        |> json(%{data: group_detail_json(group)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  PUT /api/v1/groups/:id
  Update a group.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_group_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("group", id, conn.request_path))

      group ->
        case Entities.update_group(group, params) do
          {:ok, updated_group} ->
            conn
            |> put_status(:ok)
            |> json(%{data: group_detail_json(updated_group)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/groups/:id
  Delete a group.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_group_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("group", id, conn.request_path))

      group ->
        case Entities.delete_group(group) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Group deleted"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  GET /api/v1/groups/:id/entities
  Get entities in a group.
  """
  def list_entities(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_group_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("group", id, conn.request_path))

      group ->
        opts = [
          limit: parse_int(params["limit"], 50, 100),
          cursor: params["cursor"]
        ]

        {entities, meta} = Entities.list_group_members(group, opts)

        conn
        |> put_status(:ok)
        |> json(%{
          data: Enum.map(entities, &entity_summary_json/1),
          meta: meta
        })
    end
  end

  @doc """
  POST /api/v1/groups/:id/entities
  Add entities to a group.
  """
  def add_entities(conn, %{"id" => id, "entity_ids" => entity_ids}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_group_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("group", id, conn.request_path))

      %{is_smart: true} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request(
          "Cannot manually add entities to a smart group.",
          conn.request_path
        ))

      group ->
        case Entities.add_entities_to_group(group, entity_ids) do
          {:ok, updated_group} ->
            conn
            |> put_status(:ok)
            |> json(%{data: group_detail_json(updated_group)})

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  def add_entities(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("entity_ids is required.", conn.request_path))
  end

  @doc """
  DELETE /api/v1/groups/:id/entities/:entity_id
  Remove an entity from a group.
  """
  def remove_entity(conn, %{"id" => id, "entity_id" => entity_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_group_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("group", id, conn.request_path))

      %{is_smart: true} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request(
          "Cannot manually remove entities from a smart group.",
          conn.request_path
        ))

      group ->
        case Entities.remove_entity_from_group(group, entity_id) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Entity removed from group"}})

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(:bad_request)
            |> json(ErrorHelpers.bad_request(reason, conn.request_path))

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
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

  defp group_list_json(group) do
    %{
      id: group.id,
      name: group.name,
      description: group.description,
      is_smart: group.is_smart,
      entity_count: group.entity_count || 0
    }
  end

  defp group_detail_json(group) do
    base = %{
      id: group.id,
      name: group.name,
      description: group.description,
      is_smart: group.is_smart,
      entity_count: group.entity_count || 0,
      inserted_at: group.inserted_at,
      updated_at: group.updated_at
    }

    if group.is_smart do
      Map.put(base, :rules, group.rules)
    else
      base
    end
  end

  defp entity_summary_json(entity) do
    %{
      id: entity.id,
      name: entity.name,
      type: entity.type,
      avatar_url: entity.avatar_url
    }
  end
end
