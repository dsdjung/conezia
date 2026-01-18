defmodule ConeziaWeb.HealthControllerTest do
  use ConeziaWeb.ConnCase, async: true

  describe "GET /api/v1/health" do
    test "returns health status", %{conn: conn} do
      conn = get(conn, "/api/v1/health")
      assert %{"status" => "healthy", "version" => _, "timestamp" => _} = json_response(conn, 200)
    end
  end
end
