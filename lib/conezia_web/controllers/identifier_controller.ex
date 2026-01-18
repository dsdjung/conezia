defmodule ConeziaWeb.IdentifierController do
  @moduledoc """
  Controller for identifier management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/identifiers
  List identifiers, optionally filtered by entity or type.
  """
  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      entity_id: params["entity_id"],
      type: params["type"]
    ]

    identifiers = Entities.list_identifiers(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(identifiers, &identifier_json/1)})
  end

  @doc """
  POST /api/v1/identifiers
  Create a new identifier.
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
        case Entities.create_identifier(params) do
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
  GET /api/v1/identifiers/:id
  Get a single identifier.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_identifier_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("identifier", id, conn.request_path))

      identifier ->
        conn
        |> put_status(:ok)
        |> json(%{data: identifier_json(identifier)})
    end
  end

  @doc """
  PUT /api/v1/identifiers/:id
  Update an identifier.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_identifier_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("identifier", id, conn.request_path))

      identifier ->
        case Entities.update_identifier(identifier, params) do
          {:ok, updated_identifier} ->
            conn
            |> put_status(:ok)
            |> json(%{data: identifier_json(updated_identifier)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/identifiers/:id
  Delete an identifier.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Entities.get_identifier_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("identifier", id, conn.request_path))

      identifier ->
        case Entities.delete_identifier(identifier) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Identifier deleted"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  GET /api/v1/identifiers/check
  Check if an identifier exists (for duplicate detection).
  """
  def check(conn, %{"type" => type, "value" => value}) do
    user = Guardian.Plug.current_resource(conn)

    matches = Entities.find_identifiers_by_value(user.id, type, value)

    conn
    |> put_status(:ok)
    |> json(%{
      data: %{
        exists: length(matches) > 0,
        matches: Enum.map(matches, &identifier_match_json/1)
      }
    })
  end

  def check(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("type and value are required.", conn.request_path))
  end

  # Private helpers

  defp identifier_json(identifier) do
    %{
      id: identifier.id,
      entity_id: identifier.entity_id,
      type: identifier.type,
      value: identifier.value,
      label: identifier.label,
      is_primary: identifier.is_primary,
      verified_at: identifier.verified_at
    }
  end

  defp identifier_match_json(identifier) do
    %{
      entity_id: identifier.entity_id,
      entity_name: identifier.entity.name,
      identifier_id: identifier.id,
      is_primary: identifier.is_primary
    }
  end
end
