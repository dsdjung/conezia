defmodule ConeziaWeb.Plugs.AuthRateLimiterTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias ConeziaWeb.Plugs.AuthRateLimiter

  setup do
    # Clear ETS table before each test
    case :ets.whereis(:conezia_auth_rate_limits) do
      :undefined -> :ok
      _ref -> :ets.delete_all_objects(:conezia_auth_rate_limits)
    end
    :ok
  end

  describe "login rate limiting" do
    test "allows requests under the limit" do
      conn =
        :post
        |> conn("/api/v1/auth/login")
        |> AuthRateLimiter.call(action: :login)

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-remaining") != []
    end

    test "blocks requests over the limit" do
      # Make 6 requests (limit is 5/minute)
      for _ <- 1..6 do
        :post
        |> conn("/api/v1/auth/login")
        |> AuthRateLimiter.call(action: :login)
      end

      conn =
        :post
        |> conn("/api/v1/auth/login")
        |> AuthRateLimiter.call(action: :login)

      assert conn.halted
      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
    end
  end

  describe "registration rate limiting" do
    test "allows requests under the limit" do
      conn =
        :post
        |> conn("/api/v1/auth/register")
        |> AuthRateLimiter.call(action: :register)

      refute conn.halted
    end
  end

  describe "failed login tracking" do
    test "records failed login attempts" do
      email = "test@example.com"

      assert AuthRateLimiter.failed_login_count(email) == 0

      AuthRateLimiter.record_failed_login(email)
      assert AuthRateLimiter.failed_login_count(email) == 1

      AuthRateLimiter.record_failed_login(email)
      assert AuthRateLimiter.failed_login_count(email) == 2
    end

    test "clears failed login attempts" do
      email = "test@example.com"

      AuthRateLimiter.record_failed_login(email)
      AuthRateLimiter.record_failed_login(email)
      assert AuthRateLimiter.failed_login_count(email) == 2

      AuthRateLimiter.clear_failed_logins(email)
      assert AuthRateLimiter.failed_login_count(email) == 0
    end

    test "normalizes email to lowercase" do
      AuthRateLimiter.record_failed_login("Test@Example.COM")
      assert AuthRateLimiter.failed_login_count("test@example.com") == 1
    end
  end
end
