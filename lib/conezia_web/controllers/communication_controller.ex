defmodule ConeziaWeb.CommunicationController do
  @moduledoc """
  Controller for communication/message endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Communications
  alias Conezia.Entities
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  POST /api/v1/communications
  Send a new message/communication.
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

        case Communications.create_communication(attrs) do
          {:ok, communication} ->
            conn
            |> put_status(:created)
            |> json(%{data: communication_json(communication)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  # Private helpers

  defp communication_json(communication) do
    %{
      id: communication.id,
      direction: communication.direction,
      channel: communication.channel,
      content: communication.content,
      sent_at: communication.sent_at,
      read_at: communication.read_at,
      conversation_id: communication.conversation_id,
      entity_id: communication.entity_id,
      inserted_at: communication.inserted_at
    }
  end
end
