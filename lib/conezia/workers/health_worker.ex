defmodule Conezia.Workers.HealthWorker do
  @moduledoc """
  Oban worker for processing relationship health alerts and weekly digests.
  """
  use Oban.Worker, queue: :health, max_attempts: 3

  alias Conezia.Health
  alias Conezia.Accounts.User
  alias Conezia.Repo
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "process_health_alerts", "user_id" => user_id}}) do
    result = Health.process_health_alerts(user_id)
    {:ok, result}
  end

  def perform(%Oban.Job{args: %{"action" => "process_all_health_alerts"}}) do
    users = from(u in User) |> Repo.all()

    results = Enum.map(users, fn user ->
      result = Health.process_health_alerts(user.id)
      {user.id, result}
    end)

    {:ok, %{processed_users: length(results)}}
  end

  def perform(%Oban.Job{args: %{"action" => "send_weekly_digest", "user_id" => user_id}}) do
    digest = Health.generate_weekly_digest(user_id)
    send_digest_email(user_id, digest)
    {:ok, digest}
  end

  def perform(%Oban.Job{args: %{"action" => "send_all_weekly_digests"}}) do
    # Only send to users who have email notifications enabled
    users = from(u in User,
      where: fragment("(?->>'email')::boolean = true", u.notification_preferences)
    )
    |> Repo.all()

    Enum.each(users, fn user ->
      enqueue_weekly_digest(user.id)
    end)

    {:ok, %{enqueued: length(users)}}
  end

  defp send_digest_email(_user_id, _digest) do
    # TODO: Implement email sending
    # This would use a mailer like Swoosh
    :ok
  end

  @doc """
  Enqueue health alert processing for a specific user.
  """
  def enqueue_health_alerts(user_id) do
    %{action: "process_health_alerts", user_id: user_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueue health alert processing for all users.
  Should be called daily by a cron-like scheduler.
  """
  def enqueue_all_health_alerts do
    %{action: "process_all_health_alerts"}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueue weekly digest for a specific user.
  """
  def enqueue_weekly_digest(user_id) do
    %{action: "send_weekly_digest", user_id: user_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueue weekly digests for all users.
  Should be called weekly by a cron-like scheduler.
  """
  def enqueue_all_weekly_digests do
    %{action: "send_all_weekly_digests"}
    |> new()
    |> Oban.insert()
  end
end
