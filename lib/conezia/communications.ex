defmodule Conezia.Communications do
  @moduledoc """
  The Communications context for managing conversations and messages.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Communications.{Conversation, Communication}

  # Conversation functions

  def get_conversation(id), do: Repo.get(Conversation, id)

  def get_conversation!(id), do: Repo.get!(Conversation, id)

  def get_conversation_for_user(id, user_id) do
    Conversation
    |> where([c], c.id == ^id and c.user_id == ^user_id)
    |> Repo.one()
  end

  def list_conversations(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    entity_id = Keyword.get(opts, :entity_id)
    channel = Keyword.get(opts, :channel)
    archived = Keyword.get(opts, :archived, false)

    query = from c in Conversation,
      where: c.user_id == ^user_id,
      limit: ^limit,
      offset: ^offset,
      order_by: [desc: c.last_message_at],
      preload: [:entity]

    conversations = query
    |> filter_by_entity(entity_id)
    |> filter_by_channel(channel)
    |> filter_by_archived(archived)
    |> Repo.all()

    {conversations, %{has_more: length(conversations) >= limit, next_cursor: nil}}
  end

  defp filter_by_entity(query, nil), do: query
  defp filter_by_entity(query, entity_id), do: where(query, [c], c.entity_id == ^entity_id)

  defp filter_by_channel(query, nil), do: query
  defp filter_by_channel(query, channel), do: where(query, [c], c.channel == ^channel)

  defp filter_by_archived(query, true), do: where(query, [c], c.is_archived == true)
  defp filter_by_archived(query, _), do: where(query, [c], c.is_archived == false)

  def create_conversation(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  def archive_conversation(%Conversation{} = conversation) do
    conversation
    |> Ecto.Changeset.change(is_archived: true)
    |> Repo.update()
  end

  # Communication functions

  def get_communication(id), do: Repo.get(Communication, id)

  def get_communication!(id), do: Repo.get!(Communication, id)

  def list_communications_for_conversation(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_cursor = Keyword.get(opts, :before)

    query = from c in Communication,
      where: c.conversation_id == ^conversation_id,
      limit: ^limit,
      order_by: [desc: c.sent_at, desc: c.inserted_at]

    query
    |> filter_before_cursor(before_cursor)
    |> Repo.all()
  end

  defp filter_before_cursor(query, nil), do: query
  defp filter_before_cursor(query, cursor) do
    case DateTime.from_iso8601(cursor) do
      {:ok, datetime, _} -> where(query, [c], c.sent_at < ^datetime)
      _ -> query
    end
  end

  def list_communications_for_entity(entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Communication
    |> where([c], c.entity_id == ^entity_id)
    |> limit(^limit)
    |> order_by([c], desc: c.sent_at)
    |> Repo.all()
  end

  def create_communication(attrs) do
    Repo.transaction(fn ->
      changeset = Communication.changeset(%Communication{}, attrs)

      case Repo.insert(changeset) do
        {:ok, communication} ->
          # Update conversation last_message_at if part of a conversation
          if communication.conversation_id do
            update_conversation_last_message(communication.conversation_id)
          end

          # Touch entity interaction timestamp
          if communication.entity_id do
            Conezia.Entities.touch_entity_interaction(
              Conezia.Entities.get_entity!(communication.entity_id)
            )
          end

          communication

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp update_conversation_last_message(conversation_id) do
    Conversation
    |> where([c], c.id == ^conversation_id)
    |> Repo.update_all(set: [last_message_at: DateTime.utc_now()])
  end

  def update_communication(%Communication{} = communication, attrs) do
    communication
    |> Communication.changeset(attrs)
    |> Repo.update()
  end

  def delete_communication(%Communication{} = communication) do
    Repo.delete(communication)
  end

  def mark_communication_as_read(%Communication{} = communication) do
    communication
    |> Ecto.Changeset.change(read_at: DateTime.utc_now())
    |> Repo.update()
  end

  def get_conversation_for_user(id, user_id, opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)

    case get_conversation_for_user(id, user_id) do
      nil -> nil
      conversation ->
        communications = list_communications_for_conversation(id, limit: limit)

        conversation
        |> Map.put(:communications, communications)
        |> Map.put(:has_more_messages, length(communications) >= limit)
        |> Map.put(:before_cursor, nil)
    end
  end

  def list_conversations_for_entity(entity_id, user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    conversations = from(c in Conversation,
      where: c.entity_id == ^entity_id and c.user_id == ^user_id,
      order_by: [desc: c.last_message_at],
      limit: ^limit,
      preload: [:entity]
    )
    |> Repo.all()

    {conversations, %{has_more: false, next_cursor: nil}}
  end

  def search_communications(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(c in Communication,
      join: conv in Conversation, on: c.conversation_id == conv.id,
      where: conv.user_id == ^user_id,
      where: ilike(c.content, ^"%#{query}%") or ilike(c.subject, ^"%#{query}%"),
      select: %{c | match_context: fragment("substring(? from 1 for 100)", c.content), score: 1.0},
      order_by: [desc: c.sent_at],
      limit: ^limit,
      preload: [:entity]
    )
    |> Repo.all()
  end
end
