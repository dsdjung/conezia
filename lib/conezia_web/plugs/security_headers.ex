defmodule ConeziaWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Plug for adding security headers to HTTP responses.

  Adds the following headers:
  - X-Content-Type-Options: nosniff
  - X-Frame-Options: DENY
  - X-XSS-Protection: 1; mode=block
  - Referrer-Policy: strict-origin-when-cross-origin
  - Content-Security-Policy: default-src 'self'
  - Permissions-Policy: various restrictive policies

  HSTS is handled separately in production via force_ssl configuration.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("content-security-policy", content_security_policy())
    |> put_resp_header("permissions-policy", permissions_policy())
    |> put_resp_header("cache-control", "no-store, max-age=0")
  end

  defp content_security_policy do
    [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self'",
      "img-src 'self' data: https:",
      "font-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "upgrade-insecure-requests"
    ]
    |> Enum.join("; ")
  end

  defp permissions_policy do
    [
      "accelerometer=()",
      "camera=()",
      "geolocation=()",
      "gyroscope=()",
      "magnetometer=()",
      "microphone=()",
      "payment=()",
      "usb=()"
    ]
    |> Enum.join(", ")
  end
end
