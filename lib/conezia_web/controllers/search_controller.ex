defmodule ConeziaWeb.SearchController do
  @moduledoc """
  Controller for global search endpoint.
  """
  use ConeziaWeb, :controller

  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/search
  Global search across entities, interactions, and communications.
  """
  def search(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    case params["q"] do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request("Search query (q) is required.", conn.request_path))

      "" ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request("Search query (q) cannot be empty.", conn.request_path))

      query ->
        started_at = System.monotonic_time(:millisecond)

        opts = [
          type: params["type"],
          entity_type: params["entity_type"],
          tags: params["tags"],
          date_from: parse_date(params["date_from"]),
          date_to: parse_date(params["date_to"]),
          limit: parse_int(params["limit"], 10, 50)
        ]

        results = perform_search(user.id, query, opts)

        search_time_ms = System.monotonic_time(:millisecond) - started_at

        total_results =
          length(Map.get(results, :entities, [])) +
          length(Map.get(results, :interactions, [])) +
          length(Map.get(results, :communications, []))

        conn
        |> put_status(:ok)
        |> json(%{
          data: results,
          meta: %{
            query: query,
            total_results: total_results,
            search_time_ms: search_time_ms
          }
        })
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

  defp parse_date(nil), do: nil
  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp perform_search(user_id, query, opts) do
    type_filter = opts[:type]

    results = %{}

    results =
      if type_filter == nil or type_filter == "entity" do
        entities = search_entities(user_id, query, opts)
        Map.put(results, :entities, entities)
      else
        results
      end

    results =
      if type_filter == nil or type_filter == "interaction" do
        interactions = search_interactions(user_id, query, opts)
        Map.put(results, :interactions, interactions)
      else
        results
      end

    if type_filter == nil or type_filter == "communication" do
      communications = search_communications(user_id, query, opts)
      Map.put(results, :communications, communications)
    else
      results
    end
  end

  defp search_entities(user_id, query, opts) do
    # Use full-text search for entities
    Conezia.Entities.search_entities(user_id, query, opts)
    |> Enum.map(&entity_search_result/1)
  end

  defp search_interactions(user_id, query, opts) do
    Conezia.Interactions.search_interactions(user_id, query, opts)
    |> Enum.map(&interaction_search_result/1)
  end

  defp search_communications(user_id, query, opts) do
    Conezia.Communications.search_communications(user_id, query, opts)
    |> Enum.map(&communication_search_result/1)
  end

  defp entity_search_result(entity) do
    %{
      id: entity.id,
      name: entity.name,
      type: entity.type,
      match_context: entity.match_context,
      score: entity.score || 1.0
    }
  end

  defp interaction_search_result(interaction) do
    %{
      id: interaction.id,
      type: interaction.type,
      title: interaction.title,
      entity: %{
        id: interaction.entity_id,
        name: interaction.entity.name
      },
      match_context: interaction.match_context,
      occurred_at: interaction.occurred_at,
      score: interaction.score || 1.0
    }
  end

  defp communication_search_result(communication) do
    %{
      id: communication.id,
      channel: communication.channel,
      entity: %{
        id: communication.entity_id,
        name: communication.entity.name
      },
      match_context: communication.match_context,
      sent_at: communication.sent_at,
      score: communication.score || 1.0
    }
  end
end
