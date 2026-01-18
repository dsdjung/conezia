defmodule ConeziaWeb.ActivityController do
  @moduledoc """
  Controller for activity log endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Interactions
  alias Conezia.Guardian

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/activity
  List activity logs for the current user.
  """
  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    opts = [
      resource_type: params["resource_type"],
      action: params["action"],
      since: parse_datetime(params["since"]),
      limit: parse_int(params["limit"], 50, 100),
      cursor: params["cursor"]
    ]

    {activities, meta} = Interactions.list_activity_logs(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(activities, &activity_json/1),
      meta: meta
    })
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

  defp activity_json(activity) do
    %{
      id: activity.id,
      action: activity.action,
      resource_type: activity.resource_type,
      resource_id: activity.resource_id,
      resource_name: activity.metadata["resource_name"],
      metadata: activity.metadata,
      inserted_at: activity.inserted_at
    }
  end
end
