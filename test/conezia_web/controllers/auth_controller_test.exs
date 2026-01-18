defmodule ConeziaWeb.AuthControllerTest do
  use ConeziaWeb.ConnCase, async: true

  import Conezia.Factory

  describe "POST /api/v1/auth/register" do
    test "registers a new user with valid data", %{conn: conn} do
      attrs = %{
        email: "newuser@example.com",
        password: "Password123",
        name: "New User"
      }

      conn = post(conn, "/api/v1/auth/register", attrs)
      assert %{"data" => %{"user" => user, "token" => token}} = json_response(conn, 201)
      assert user["email"] == "newuser@example.com"
      assert user["name"] == "New User"
      assert token["access_token"]
      assert token["token_type"] == "Bearer"
    end

    test "returns error with invalid email", %{conn: conn} do
      attrs = %{email: "invalid", password: "Password123"}
      conn = post(conn, "/api/v1/auth/register", attrs)
      assert %{"error" => error} = json_response(conn, 422)
      assert error["status"] == 422
    end

    test "returns error with weak password", %{conn: conn} do
      attrs = %{email: "test@example.com", password: "weak"}
      conn = post(conn, "/api/v1/auth/register", attrs)
      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns error with duplicate email", %{conn: conn} do
      insert(:user, email: "existing@example.com")
      attrs = %{email: "existing@example.com", password: "Password123"}
      conn = post(conn, "/api/v1/auth/register", attrs)
      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "POST /api/v1/auth/login" do
    test "logs in with valid credentials", %{conn: conn} do
      user = insert(:user, email: "test@example.com", hashed_password: Argon2.hash_pwd_salt("Password123"))

      conn = post(conn, "/api/v1/auth/login", %{email: "test@example.com", password: "Password123"})
      assert %{"data" => %{"user" => user_data, "token" => token}} = json_response(conn, 200)
      assert user_data["id"] == user.id
      assert token["access_token"]
    end

    test "returns unauthorized with wrong password", %{conn: conn} do
      insert(:user, email: "test@example.com", hashed_password: Argon2.hash_pwd_salt("Password123"))

      conn = post(conn, "/api/v1/auth/login", %{email: "test@example.com", password: "WrongPassword"})
      assert %{"error" => error} = json_response(conn, 401)
      assert error["status"] == 401
    end

    test "returns unauthorized with non-existent email", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/login", %{email: "nonexistent@example.com", password: "Password123"})
      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns bad request without credentials", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/login", %{})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "POST /api/v1/auth/refresh" do
    test "refreshes token with valid token", %{conn: conn} do
      user = insert(:user)
      {:ok, token, _claims} = Conezia.Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/auth/refresh")

      assert %{"data" => %{"token" => new_token}} = json_response(conn, 200)
      assert new_token["access_token"]
    end

    test "returns unauthorized without token", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/refresh")
      assert %{"error" => _} = json_response(conn, 401)
    end
  end

  describe "GET /api/v1/auth/me" do
    test "returns current user with valid token", %{conn: conn} do
      user = insert(:user)
      {:ok, token, _claims} = Conezia.Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/auth/me")

      assert %{"data" => user_data} = json_response(conn, 200)
      assert user_data["id"] == user.id
      assert user_data["email"] == user.email
    end

    test "returns unauthorized without token", %{conn: conn} do
      conn = get(conn, "/api/v1/auth/me")
      assert %{"error" => _} = json_response(conn, 401)
    end
  end
end
