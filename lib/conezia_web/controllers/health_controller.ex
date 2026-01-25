defmodule ConeziaWeb.HealthController do
  @moduledoc """
  Controller for health check and relationship health endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Entities
  alias Conezia.Guardian

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/health
  System health check endpoint (public, no auth required).
  """
  def index(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{
      status: "healthy",
      version: Application.spec(:conezia, :vsn) |> to_string(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc """
  GET /api/v1/health/summary
  Get a summary of relationship health for the current user.
  """
  def summary(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    summary = Entities.get_health_summary(user.id)

    conn
    |> put_status(:ok)
    |> json(%{data: summary})
  end

  @doc """
  GET /api/v1/health/digest
  Get the weekly digest for the current user.
  """
  def digest(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    digest = Entities.get_weekly_digest(user.id)

    conn
    |> put_status(:ok)
    |> json(%{data: digest})
  end
end
