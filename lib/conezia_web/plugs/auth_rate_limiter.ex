defmodule ConeziaWeb.Plugs.AuthRateLimiter do
  @moduledoc """
  Stricter rate limiting plug specifically for authentication endpoints.

  Implements:
  - Very low limits for login attempts (5 per minute per IP)
  - Password reset limits (3 per hour per email)
  - Registration limits (10 per hour per IP)

  This is separate from the general API rate limiter to provide
  stronger protection against brute-force and credential stuffing attacks.
  """
  import Plug.Conn
  import Phoenix.Controller

  # ETS table name for auth rate limits
  @table_name :conezia_auth_rate_limits

  # Rate limits for different auth operations
  @login_limit_per_minute 5
  @password_reset_limit_per_hour 3
  @registration_limit_per_hour 10
  @verification_limit_per_hour 5

  def init(opts), do: opts

  def call(conn, opts) do
    ensure_table_exists()

    action = Keyword.get(opts, :action, :general)
    check_auth_rate_limit(conn, action)
  end

  defp check_auth_rate_limit(conn, :login) do
    ip = get_client_ip(conn)
    key = "login:#{ip}"
    check_limit(conn, key, @login_limit_per_minute, 60, "Too many login attempts. Please try again later.")
  end

  defp check_auth_rate_limit(conn, :register) do
    ip = get_client_ip(conn)
    key = "register:#{ip}"
    check_limit(conn, key, @registration_limit_per_hour, 3600, "Too many registration attempts. Please try again later.")
  end

  defp check_auth_rate_limit(conn, :forgot_password) do
    ip = get_client_ip(conn)
    key = "forgot_password:#{ip}"
    check_limit(conn, key, @password_reset_limit_per_hour, 3600, "Too many password reset requests. Please try again later.")
  end

  defp check_auth_rate_limit(conn, :verify_email) do
    ip = get_client_ip(conn)
    key = "verify_email:#{ip}"
    check_limit(conn, key, @verification_limit_per_hour, 3600, "Too many verification attempts. Please try again later.")
  end

  defp check_auth_rate_limit(conn, _action), do: conn

  defp check_limit(conn, key, limit, window_seconds, error_message) do
    now = System.system_time(:second)
    window_start = div(now, window_seconds) * window_seconds
    window_key = "#{key}:#{window_start}"

    count = get_and_increment(window_key, window_seconds)

    if count > limit do
      retry_after = window_start + window_seconds - now

      conn
      |> put_resp_header("retry-after", to_string(retry_after))
      |> put_resp_header("x-ratelimit-limit", to_string(limit))
      |> put_resp_header("x-ratelimit-remaining", "0")
      |> put_resp_header("x-ratelimit-reset", to_string(window_start + window_seconds))
      |> put_status(:too_many_requests)
      |> json(%{
        error: %{
          type: "https://api.conezia.com/errors/rate-limited",
          title: "Rate Limit Exceeded",
          status: 429,
          detail: error_message,
          retry_after: retry_after
        }
      })
      |> halt()
    else
      conn
      |> put_resp_header("x-ratelimit-limit", to_string(limit))
      |> put_resp_header("x-ratelimit-remaining", to_string(max(0, limit - count)))
      |> put_resp_header("x-ratelimit-reset", to_string(window_start + window_seconds))
    end
  end

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}])

      _ ->
        :ok
    end
  end

  defp get_and_increment(key, ttl_seconds) do
    now = System.system_time(:second)

    case :ets.lookup(@table_name, key) do
      [{^key, count, expires_at}] when expires_at > now ->
        :ets.update_counter(@table_name, key, {2, 1})
        count + 1

      _ ->
        # Entry doesn't exist or has expired
        :ets.insert(@table_name, {key, 1, now + ttl_seconds})
        1
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> Tuple.to_list()
        |> Enum.join(".")
    end
  end

  @doc """
  Record a failed login attempt. Call this when login credentials are invalid.
  This is used for account lockout tracking separate from rate limiting.
  """
  def record_failed_login(email) do
    ensure_table_exists()
    key = "failed_login:#{String.downcase(email)}"
    now = System.system_time(:second)
    # Track failed attempts for 1 hour
    ttl = 3600

    case :ets.lookup(@table_name, key) do
      [{^key, count, expires_at}] when expires_at > now ->
        :ets.update_counter(@table_name, key, {2, 1})
        count + 1

      _ ->
        :ets.insert(@table_name, {key, 1, now + ttl})
        1
    end
  end

  @doc """
  Check if an account should be locked due to too many failed attempts.
  Returns the number of failed attempts in the current window.
  """
  def failed_login_count(email) do
    ensure_table_exists()
    key = "failed_login:#{String.downcase(email)}"
    now = System.system_time(:second)

    case :ets.lookup(@table_name, key) do
      [{^key, count, expires_at}] when expires_at > now -> count
      _ -> 0
    end
  end

  @doc """
  Clear failed login attempts after successful login.
  """
  def clear_failed_logins(email) do
    ensure_table_exists()
    key = "failed_login:#{String.downcase(email)}"
    :ets.delete(@table_name, key)
    :ok
  end
end
