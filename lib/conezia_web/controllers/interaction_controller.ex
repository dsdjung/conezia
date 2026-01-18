defmodule ConeziaWeb.InteractionController do
  @moduledoc """
  Controller for interaction management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Interactions
  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/interactions
  List all interactions for the current user.
  """
  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      entity_id: params["entity_id"],
      type: params["type"],
      since: parse_datetime(params["since"]),
      until: parse_datetime(params["until"]),
      limit: parse_int(params["limit"], 50, 100),
      cursor: params["cursor"]
    ]

    {interactions, meta} = Interactions.list_interactions(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(interactions, &interaction_json/1),
      meta: meta
    })
  end

  @doc """
  GET /api/v1/interactions/:id
  Get a single interaction.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Interactions.get_interaction_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("interaction", id, conn.request_path))

      interaction ->
        conn
        |> put_status(:ok)
        |> json(%{data: interaction_detail_json(interaction)})
    end
  end

  @doc """
  POST /api/v1/interactions
  Create a new interaction.
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

        case Interactions.create_interaction(attrs) do
          {:ok, interaction} ->
            conn
            |> put_status(:created)
            |> json(%{data: interaction_detail_json(interaction)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  PUT /api/v1/interactions/:id
  Update an interaction.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Interactions.get_interaction_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("interaction", id, conn.request_path))

      interaction ->
        case Interactions.update_interaction(interaction, params) do
          {:ok, updated_interaction} ->
            conn
            |> put_status(:ok)
            |> json(%{data: interaction_detail_json(updated_interaction)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/interactions/:id
  Delete an interaction.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Interactions.get_interaction_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("interaction", id, conn.request_path))

      interaction ->
        case Interactions.delete_interaction(interaction) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Interaction deleted"}})

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

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp interaction_json(interaction) do
    %{
      id: interaction.id,
      type: interaction.type,
      title: interaction.title,
      content: truncate(interaction.content, 200),
      occurred_at: interaction.occurred_at,
      entity: entity_summary_json(interaction.entity),
      attachments: [],
      inserted_at: interaction.inserted_at
    }
  end

  defp interaction_detail_json(interaction) do
    %{
      id: interaction.id,
      type: interaction.type,
      title: interaction.title,
      content: interaction.content,
      occurred_at: interaction.occurred_at,
      entity: entity_summary_json(interaction.entity),
      metadata: interaction.metadata,
      attachments: Enum.map(interaction.attachments || [], &attachment_json/1),
      inserted_at: interaction.inserted_at,
      updated_at: interaction.updated_at
    }
  end

  defp entity_summary_json(nil), do: nil
  defp entity_summary_json(%Ecto.Association.NotLoaded{}), do: nil
  defp entity_summary_json(entity) do
    %{
      id: entity.id,
      name: entity.name,
      avatar_url: entity.avatar_url
    }
  end

  defp attachment_json(attachment) do
    %{
      id: attachment.id,
      filename: attachment.filename,
      mime_type: attachment.mime_type,
      size_bytes: attachment.size_bytes
    }
  end

  defp truncate(nil, _length), do: nil
  defp truncate(string, length) when byte_size(string) <= length, do: string
  defp truncate(string, length) do
    String.slice(string, 0, length) <> "..."
  end
end
