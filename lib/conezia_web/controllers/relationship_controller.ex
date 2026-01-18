defmodule ConeziaWeb.RelationshipController do
  @moduledoc """
  Controller for relationship management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/relationships
  List all relationships for the current user.
  """
  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      type: params["type"],
      status: params["status"],
      health: params["health"],
      limit: parse_int(params["limit"], 50, 100),
      cursor: params["cursor"]
    ]

    {relationships, meta} = Entities.list_relationships(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(relationships, &relationship_json/1),
      meta: meta
    })
  end

  @doc """
  POST /api/v1/relationships
  Create a new relationship.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    # Verify the entity belongs to the user
    case Entities.get_entity_for_user(params["entity_id"], user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("entity", params["entity_id"], conn.request_path))

      _entity ->
        attrs = Map.put(params, "user_id", user.id)

        case Entities.create_relationship(attrs) do
          {:ok, relationship} ->
            conn
            |> put_status(:created)
            |> json(%{data: relationship_json(relationship)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  GET /api/v1/relationships/:id
  Get a single relationship.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_relationship_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("relationship", id, conn.request_path))

      relationship ->
        conn
        |> put_status(:ok)
        |> json(%{data: relationship_json(relationship)})
    end
  end

  @doc """
  PUT /api/v1/relationships/:id
  Update a relationship.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_relationship_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("relationship", id, conn.request_path))

      relationship ->
        case Entities.update_relationship(relationship, params) do
          {:ok, updated_relationship} ->
            conn
            |> put_status(:ok)
            |> json(%{data: relationship_json(updated_relationship)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/relationships/:id
  Delete a relationship.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_relationship_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("relationship", id, conn.request_path))

      relationship ->
        case Entities.delete_relationship(relationship) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Relationship deleted"}})

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

  defp relationship_json(relationship) do
    %{
      id: relationship.id,
      entity_id: relationship.entity_id,
      type: relationship.type,
      strength: relationship.strength,
      status: relationship.status,
      started_at: relationship.started_at,
      health_threshold_days: relationship.health_threshold_days,
      last_interaction_at: relationship.last_interaction_at,
      notes: relationship.notes,
      entity: entity_summary_json(relationship.entity),
      health_score: calculate_health_score(relationship),
      inserted_at: relationship.inserted_at,
      updated_at: relationship.updated_at
    }
  end

  defp entity_summary_json(nil), do: nil
  defp entity_summary_json(entity) do
    %{
      id: entity.id,
      name: entity.name,
      type: entity.type,
      avatar_url: entity.avatar_url
    }
  end

  defp calculate_health_score(relationship) do
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
end
