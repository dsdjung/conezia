defmodule Conezia.Interactions do
  @moduledoc """
  The Interactions context for managing notes, meetings, and other interactions.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Interactions.{Interaction, ActivityLog}

  # Interaction functions

  def get_interaction(id), do: Repo.get(Interaction, id)

  def get_interaction!(id), do: Repo.get!(Interaction, id)

  def get_interaction_for_user(id, user_id) do
    Interaction
    |> where([i], i.id == ^id and i.user_id == ^user_id)
    |> Repo.one()
  end

  def list_interactions(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    entity_id = Keyword.get(opts, :entity_id)
    type = Keyword.get(opts, :type)
    since = Keyword.get(opts, :since)
    until_date = Keyword.get(opts, :until)

    query = from i in Interaction,
      where: i.user_id == ^user_id,
      limit: ^limit,
      offset: ^offset,
      order_by: [desc: i.occurred_at],
      preload: [:entity]

    query
    |> filter_by_entity_id(entity_id)
    |> filter_by_type(type)
    |> filter_by_since(since)
    |> filter_by_until(until_date)
    |> Repo.all()
  end

  defp filter_by_entity_id(query, nil), do: query
  defp filter_by_entity_id(query, entity_id), do: where(query, [i], i.entity_id == ^entity_id)

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [i], i.type == ^type)

  defp filter_by_since(query, nil), do: query
  defp filter_by_since(query, since) do
    case DateTime.from_iso8601(since) do
      {:ok, datetime, _} -> where(query, [i], i.occurred_at >= ^datetime)
      _ -> query
    end
  end

  defp filter_by_until(query, nil), do: query
  defp filter_by_until(query, until_date) do
    case DateTime.from_iso8601(until_date) do
      {:ok, datetime, _} -> where(query, [i], i.occurred_at <= ^datetime)
      _ -> query
    end
  end

  def create_interaction(attrs) do
    Repo.transaction(fn ->
      changeset = Interaction.changeset(%Interaction{}, attrs)

      case Repo.insert(changeset) do
        {:ok, interaction} ->
          # Touch entity interaction timestamp
          if interaction.entity_id do
            Conezia.Entities.touch_entity_interaction(
              Conezia.Entities.get_entity!(interaction.entity_id)
            )
          end

          interaction

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_interaction(%Interaction{} = interaction, attrs) do
    interaction
    |> Interaction.changeset(attrs)
    |> Repo.update()
  end

  def delete_interaction(%Interaction{} = interaction) do
    Repo.delete(interaction)
  end

  # Activity Log functions

  def list_activity_logs(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    resource_type = Keyword.get(opts, :resource_type)
    action = Keyword.get(opts, :action)
    since = Keyword.get(opts, :since)

    query = from a in ActivityLog,
      where: a.user_id == ^user_id,
      limit: ^limit,
      order_by: [desc: a.inserted_at]

    query
    |> filter_log_by_resource_type(resource_type)
    |> filter_log_by_action(action)
    |> filter_log_by_since(since)
    |> Repo.all()
  end

  defp filter_log_by_resource_type(query, nil), do: query
  defp filter_log_by_resource_type(query, type), do: where(query, [a], a.resource_type == ^type)

  defp filter_log_by_action(query, nil), do: query
  defp filter_log_by_action(query, action), do: where(query, [a], a.action == ^action)

  defp filter_log_by_since(query, nil), do: query
  defp filter_log_by_since(query, since) do
    case DateTime.from_iso8601(since) do
      {:ok, datetime, _} -> where(query, [a], a.inserted_at >= ^datetime)
      _ -> query
    end
  end

  def log_activity(user, action, resource_type, resource_id \\ nil, metadata \\ %{}, conn \\ nil) do
    attrs = %{
      user_id: user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata,
      ip_address: conn && get_ip(conn),
      user_agent: conn && get_user_agent(conn)
    }

    %ActivityLog{}
    |> ActivityLog.changeset(attrs)
    |> Repo.insert()
  end

  defp get_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> String.slice(ua, 0, 512)
      _ -> nil
    end
  end

  def list_interactions_for_entity(entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    interactions = from(i in Interaction,
      where: i.entity_id == ^entity_id,
      order_by: [desc: i.occurred_at],
      limit: ^limit,
      preload: [:entity]
    )
    |> Repo.all()

    {interactions, %{has_more: false, next_cursor: nil}}
  end

  def list_activity_for_entity(entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    activities = from(a in ActivityLog,
      where: a.resource_type == "entity" and a.resource_id == ^entity_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
    |> Repo.all()

    {activities, %{has_more: false, next_cursor: nil}}
  end

  def search_interactions(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(i in Interaction,
      where: i.user_id == ^user_id,
      where: ilike(i.title, ^"%#{query}%") or ilike(i.content, ^"%#{query}%"),
      select: %{i | match_context: fragment("substring(? from 1 for 100)", i.content), score: 1.0},
      order_by: [desc: i.occurred_at],
      limit: ^limit,
      preload: [:entity]
    )
    |> Repo.all()
  end
end
