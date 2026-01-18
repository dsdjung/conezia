defmodule ConeziaWeb.EntityControllerTest do
  use ConeziaWeb.ConnCase, async: true

  import Conezia.Factory

  setup %{conn: conn} do
    user = insert(:user)
    {:ok, token, _claims} = Conezia.Guardian.encode_and_sign(user)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")
    {:ok, conn: conn, user: user}
  end

  describe "GET /api/v1/entities" do
    test "lists entities for authenticated user", %{conn: conn, user: user} do
      insert(:entity, owner: user, name: "Entity 1")
      insert(:entity, owner: user, name: "Entity 2")

      conn = get(conn, "/api/v1/entities")
      assert %{"data" => entities, "meta" => _meta} = json_response(conn, 200)
      assert length(entities) == 2
    end

    test "filters entities by type", %{conn: conn, user: user} do
      insert(:entity, owner: user, type: "person")
      insert(:entity, owner: user, type: "organization")

      conn = get(conn, "/api/v1/entities", type: "person")
      assert %{"data" => entities} = json_response(conn, 200)
      assert length(entities) == 1
      assert hd(entities)["type"] == "person"
    end

    test "returns empty list for user with no entities", %{conn: conn} do
      conn = get(conn, "/api/v1/entities")
      assert %{"data" => []} = json_response(conn, 200)
    end
  end

  describe "GET /api/v1/entities/:id" do
    test "returns entity for authenticated user", %{conn: conn, user: user} do
      entity = insert(:entity, owner: user, name: "Test Entity")

      conn = get(conn, "/api/v1/entities/#{entity.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == entity.id
      assert data["name"] == "Test Entity"
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn = get(conn, "/api/v1/entities/#{UUID.uuid4()}")
      assert %{"error" => error} = json_response(conn, 404)
      assert error["status"] == 404
    end

    test "returns 404 for entity owned by another user", %{conn: conn} do
      other_user = insert(:user)
      entity = insert(:entity, owner: other_user)

      conn = get(conn, "/api/v1/entities/#{entity.id}")
      assert %{"error" => _} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/entities" do
    test "creates entity with valid data", %{conn: conn} do
      attrs = %{name: "New Entity", type: "person"}

      conn = post(conn, "/api/v1/entities", attrs)
      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "New Entity"
      assert data["type"] == "person"
    end

    test "returns error with missing required fields", %{conn: conn} do
      attrs = %{}

      conn = post(conn, "/api/v1/entities", attrs)
      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns error with invalid type", %{conn: conn} do
      attrs = %{name: "Test", type: "invalid_type"}

      conn = post(conn, "/api/v1/entities", attrs)
      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "PUT /api/v1/entities/:id" do
    test "updates entity with valid data", %{conn: conn, user: user} do
      entity = insert(:entity, owner: user, name: "Original Name")

      conn = put(conn, "/api/v1/entities/#{entity.id}", %{name: "Updated Name"})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["name"] == "Updated Name"
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn = put(conn, "/api/v1/entities/#{UUID.uuid4()}", %{name: "Test"})
      assert %{"error" => _} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/entities/:id" do
    test "deletes entity", %{conn: conn, user: user} do
      entity = insert(:entity, owner: user)

      conn = delete(conn, "/api/v1/entities/#{entity.id}")
      assert response(conn, 204)
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn = delete(conn, "/api/v1/entities/#{UUID.uuid4()}")
      assert %{"error" => _} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/entities/:id/archive" do
    test "archives entity", %{conn: conn, user: user} do
      entity = insert(:entity, owner: user)

      conn = post(conn, "/api/v1/entities/#{entity.id}/archive")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["archived_at"]
    end
  end

  describe "POST /api/v1/entities/:id/unarchive" do
    test "unarchives entity", %{conn: conn, user: user} do
      entity = insert(:entity, owner: user, archived_at: DateTime.utc_now())

      conn = post(conn, "/api/v1/entities/#{entity.id}/unarchive")
      assert %{"data" => data} = json_response(conn, 200)
      assert is_nil(data["archived_at"])
    end
  end

  describe "unauthenticated requests" do
    test "returns unauthorized without token" do
      conn = build_conn()
      conn = get(conn, "/api/v1/entities")
      assert %{"error" => error} = json_response(conn, 401)
      assert error["status"] == 401
    end
  end
end
