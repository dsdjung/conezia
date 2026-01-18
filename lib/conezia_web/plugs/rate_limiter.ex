defmodule ConeziaWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug for the Conezia API.
  Implements tier-based rate limiting per user.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Conezia.Guardian

  # Rate limits per hour by tier
  @rate_limits %{
    free: 100,
    personal: 1_000,
    professional: 10_000,
    enterprise: 100_000
  }

  # ETS table name for storing rate limit counters
  @table_name :conezia_rate_limits

  def init(opts), do: opts

  def call(conn, _opts) do
    ensure_table_exists()

    case Guardian.Plug.current_resource(conn) do
      nil ->
        # For unauthenticated requests, use IP-based limiting with free tier limits
        check_rate_limit(conn, "ip:#{get_client_ip(conn)}", :free)

      user ->
        check_rate_limit(conn, "user:#{user.id}", user.tier || :free)
    end
  end

  defp check_rate_limit(conn, key, tier) do
    limit = Map.get(@rate_limits, tier, @rate_limits.free)
    window_key = "#{key}:#{current_window()}"

    {count, reset_time} = get_and_increment(window_key)

    conn
    |> put_resp_header("x-ratelimit-limit", to_string(limit))
    |> put_resp_header("x-ratelimit-remaining", to_string(max(0, limit - count)))
    |> put_resp_header("x-ratelimit-reset", to_string(reset_time))
    |> maybe_reject(count, limit)
  end

  defp maybe_reject(conn, count, limit) when count > limit do
    conn
    |> put_status(:too_many_requests)
    |> json(%{
      error: %{
        type: "https://api.conezia.com/errors/rate-limited",
        title: "Rate Limit Exceeded",
        status: 429,
        detail: "You have exceeded the rate limit of #{limit} requests per hour.",
        retry_after: seconds_until_reset()
      }
    })
    |> halt()
  end

  defp maybe_reject(conn, _count, _limit), do: conn

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}])

      _ ->
        :ok
    end
  end

  defp get_and_increment(key) do
    reset_time = next_window_start()

    case :ets.lookup(@table_name, key) do
      [{^key, count, _stored_reset}] ->
        :ets.update_counter(@table_name, key, {2, 1})
        {count + 1, reset_time}

      [] ->
        :ets.insert(@table_name, {key, 1, reset_time})
        {1, reset_time}
    end
  end

  defp current_window do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
    |> DateTime.to_unix()
  end

  defp next_window_start do
    current_window() + 3600
  end

  defp seconds_until_reset do
    next_window_start() - DateTime.to_unix(DateTime.utc_now())
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
end
