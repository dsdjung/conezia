defmodule ConeziaWeb.Plugs.SecurityHeadersTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias ConeziaWeb.Plugs.SecurityHeaders

  describe "call/2" do
    test "adds X-Content-Type-Options header" do
      conn =
        :get
        |> conn("/")
        |> SecurityHeaders.call([])

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "adds X-Frame-Options header" do
      conn =
        :get
        |> conn("/")
        |> SecurityHeaders.call([])

      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    end

    test "adds X-XSS-Protection header" do
      conn =
        :get
        |> conn("/")
        |> SecurityHeaders.call([])

      assert get_resp_header(conn, "x-xss-protection") == ["1; mode=block"]
    end

    test "adds Referrer-Policy header" do
      conn =
        :get
        |> conn("/")
        |> SecurityHeaders.call([])

      assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    end

    test "adds Content-Security-Policy header" do
      conn =
        :get
        |> conn("/")
        |> SecurityHeaders.call([])

      [csp] = get_resp_header(conn, "content-security-policy")
      assert String.contains?(csp, "default-src 'self'")
      assert String.contains?(csp, "frame-ancestors 'none'")
    end

    test "adds Permissions-Policy header" do
      conn =
        :get
        |> conn("/")
        |> SecurityHeaders.call([])

      [pp] = get_resp_header(conn, "permissions-policy")
      assert String.contains?(pp, "camera=()")
      assert String.contains?(pp, "microphone=()")
    end

    test "adds Cache-Control header" do
      conn =
        :get
        |> conn("/")
        |> SecurityHeaders.call([])

      assert get_resp_header(conn, "cache-control") == ["no-store, max-age=0"]
    end
  end
end
