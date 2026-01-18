defmodule ConeziaWeb.TagController do
  @moduledoc """
  Controller for tag management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/tags
  List all tags for the current user.
  """
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    tags = Entities.list_tags(user.id)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(tags, &tag_json/1)})
  end

  @doc """
  GET /api/v1/tags/:id
  Get a single tag.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_tag_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("tag", id, conn.request_path))

      tag ->
        conn
        |> put_status(:ok)
        |> json(%{data: tag_json(tag)})
    end
  end

  @doc """
  POST /api/v1/tags
  Create a new tag.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    attrs = Map.put(params, "user_id", user.id)

    case Entities.create_tag(attrs) do
      {:ok, tag} ->
        conn
        |> put_status(:created)
        |> json(%{data: tag_json(tag)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  PUT /api/v1/tags/:id
  Update a tag.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_tag_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("tag", id, conn.request_path))

      tag ->
        case Entities.update_tag(tag, params) do
          {:ok, updated_tag} ->
            conn
            |> put_status(:ok)
            |> json(%{data: tag_json(updated_tag)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/tags/:id
  Delete a tag.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_tag_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("tag", id, conn.request_path))

      tag ->
        case Entities.delete_tag(tag) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Tag deleted"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  # Private helpers

  defp tag_json(tag) do
    %{
      id: tag.id,
      name: tag.name,
      color: tag.color,
      description: tag.description,
      entity_count: tag.entity_count || 0
    }
  end
end
