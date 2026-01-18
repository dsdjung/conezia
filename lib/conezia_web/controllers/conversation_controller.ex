defmodule ConeziaWeb.ConversationController do
  @moduledoc """
  Controller for conversation management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Communications
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/conversations
  List all conversations for the current user.
  """
  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      entity_id: params["entity_id"],
      channel: params["channel"],
      archived: params["archived"] == "true",
      limit: parse_int(params["limit"], 50, 100),
      cursor: params["cursor"]
    ]

    {conversations, meta} = Communications.list_conversations(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(conversations, &conversation_list_json/1),
      meta: meta
    })
  end

  @doc """
  GET /api/v1/conversations/:id
  Get a single conversation with messages.
  """
  def show(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      limit: parse_int(params["limit"], 50, 100),
      before: params["before"]
    ]

    case Communications.get_conversation_for_user(id, user.id, opts) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("conversation", id, conn.request_path))

      conversation ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: conversation_detail_json(conversation),
          meta: %{
            has_more: conversation.has_more_messages,
            before_cursor: conversation.before_cursor
          }
        })
    end
  end

  @doc """
  PUT /api/v1/conversations/:id
  Update a conversation.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Communications.get_conversation_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("conversation", id, conn.request_path))

      conversation ->
        case Communications.update_conversation(conversation, params) do
          {:ok, updated_conversation} ->
            conn
            |> put_status(:ok)
            |> json(%{data: conversation_list_json(updated_conversation)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/conversations/:id
  Delete a conversation and all its messages.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Communications.get_conversation_for_user(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("conversation", id, conn.request_path))

      conversation ->
        case Communications.delete_conversation(conversation) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Conversation deleted"}})

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

  defp conversation_list_json(conversation) do
    %{
      id: conversation.id,
      entity: entity_summary_json(conversation.entity),
      channel: conversation.channel,
      subject: conversation.subject,
      last_message_at: conversation.last_message_at,
      last_message_preview: conversation.last_message_preview,
      unread_count: conversation.unread_count || 0,
      is_archived: conversation.archived_at != nil
    }
  end

  defp conversation_detail_json(conversation) do
    %{
      id: conversation.id,
      entity: entity_summary_json(conversation.entity),
      channel: conversation.channel,
      subject: conversation.subject,
      messages: Enum.map(conversation.communications || [], &message_json/1)
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

  defp message_json(communication) do
    %{
      id: communication.id,
      direction: communication.direction,
      content: communication.content,
      sent_at: communication.sent_at,
      read_at: communication.read_at,
      attachments: Enum.map(communication.attachments || [], &attachment_json/1)
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
end
