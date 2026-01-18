defmodule Conezia.Health do
  @moduledoc """
  Relationship health scoring and monitoring.

  Health is calculated based on:
  - Days since last interaction vs. threshold
  - Relationship strength setting
  - Relationship status

  Score ranges from 0-100:
  - 80-100: Healthy (green)
  - 50-79: Warning (yellow)
  - 0-49: Critical (red)
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Entities.{Entity, Relationship}
  alias Conezia.Reminders.Reminder

  @healthy_threshold 0.5  # Under 50% of threshold = healthy
  @warning_threshold 1.0  # Under 100% of threshold = warning

  @doc """
  Calculate the health score for an entity relationship.

  Returns a map with:
  - score: 0-100 numeric health score
  - status: "healthy" | "warning" | "critical"
  - days_since_interaction: number of days since last interaction
  - threshold_days: the configured threshold for this relationship
  - days_remaining: days until status degrades (if applicable)
  """
  def calculate_health_score(entity, relationship \\ nil) do
    threshold_days = get_threshold_days(relationship)
    days_since = days_since_interaction(entity)

    score = compute_score(days_since, threshold_days)
    status = determine_status(days_since, threshold_days)

    %{
      score: score,
      status: status,
      days_since_interaction: days_since,
      threshold_days: threshold_days,
      days_remaining: max(0, threshold_days - days_since),
      needs_attention: status in ["warning", "critical"]
    }
  end

  defp get_threshold_days(nil), do: 30
  defp get_threshold_days(%Relationship{health_threshold_days: days}) when is_integer(days), do: days
  defp get_threshold_days(_), do: 30

  defp days_since_interaction(%Entity{last_interaction_at: nil}), do: 999
  defp days_since_interaction(%Entity{last_interaction_at: last_at}) do
    Date.diff(Date.utc_today(), DateTime.to_date(last_at))
  end

  defp compute_score(days_since, threshold_days) do
    # Score decreases as days since interaction approaches and exceeds threshold
    ratio = days_since / threshold_days

    cond do
      ratio <= 0.25 -> 100
      ratio <= @healthy_threshold -> round(100 - (ratio * 40))  # 80-100
      ratio <= @warning_threshold -> round(80 - ((ratio - @healthy_threshold) * 60))  # 50-80
      ratio <= 1.5 -> round(50 - ((ratio - @warning_threshold) * 60))  # 20-50
      true -> max(0, round(20 - ((ratio - 1.5) * 40)))  # 0-20
    end
  end

  defp determine_status(days_since, threshold_days) do
    ratio = days_since / threshold_days

    cond do
      ratio <= @healthy_threshold -> "healthy"
      ratio <= @warning_threshold -> "warning"
      true -> "critical"
    end
  end

  @doc """
  List entities that need attention based on relationship health.

  Returns entities where the health score indicates warning or critical status.
  """
  def list_entities_needing_attention(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    entities = from(e in Entity,
      left_join: r in Relationship, on: r.entity_id == e.id and r.user_id == ^user_id,
      where: e.owner_id == ^user_id and is_nil(e.archived_at),
      where: r.status == "active" or is_nil(r.status),
      preload: [relationships: r]
    )
    |> Repo.all()

    entities
    |> Enum.map(fn entity ->
      relationship = List.first(entity.relationships)
      health = calculate_health_score(entity, relationship)

      %{
        entity: entity,
        relationship: relationship,
        health: health
      }
    end)
    |> Enum.filter(fn %{health: health} -> health.needs_attention end)
    |> Enum.sort_by(fn %{health: health} -> health.score end, :asc)
    |> Enum.take(limit)
  end

  @doc """
  Generate a weekly health digest for a user.
  """
  def generate_weekly_digest(user_id) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -7)
    start_datetime = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    # Get all active entities with relationships
    entities_with_health = from(e in Entity,
      left_join: r in Relationship, on: r.entity_id == e.id and r.user_id == ^user_id,
      where: e.owner_id == ^user_id and is_nil(e.archived_at),
      preload: [relationships: r]
    )
    |> Repo.all()
    |> Enum.map(fn entity ->
      relationship = List.first(entity.relationships)
      health = calculate_health_score(entity, relationship)
      %{entity: entity, health: health}
    end)

    # Count by status
    health_counts = Enum.reduce(entities_with_health, %{healthy: 0, warning: 0, critical: 0}, fn %{health: h}, acc ->
      Map.update!(acc, String.to_atom(h.status), &(&1 + 1))
    end)

    # Get interactions this week
    interactions_count = from(i in Conezia.Interactions.Interaction,
      join: e in Entity, on: i.entity_id == e.id,
      where: e.owner_id == ^user_id,
      where: i.occurred_at >= ^start_datetime and i.occurred_at <= ^end_datetime
    )
    |> Repo.aggregate(:count)

    # Get most interacted entities this week
    top_interactions = from(i in Conezia.Interactions.Interaction,
      join: e in Entity, on: i.entity_id == e.id,
      where: e.owner_id == ^user_id,
      where: i.occurred_at >= ^start_datetime and i.occurred_at <= ^end_datetime,
      group_by: [e.id, e.name],
      select: %{entity_id: e.id, entity_name: e.name, count: count(i.id)},
      order_by: [desc: count(i.id)],
      limit: 5
    )
    |> Repo.all()

    # Get entities that need attention
    needs_attention = entities_with_health
    |> Enum.filter(fn %{health: h} -> h.needs_attention end)
    |> Enum.sort_by(fn %{health: h} -> h.score end, :asc)
    |> Enum.take(10)
    |> Enum.map(fn %{entity: e, health: h} ->
      %{
        entity: %{id: e.id, name: e.name, avatar_url: e.avatar_url},
        health_score: h.score,
        days_since_interaction: h.days_since_interaction,
        suggested_action: suggest_action(h)
      }
    end)

    %{
      period: %{start_date: start_date, end_date: end_date},
      summary: %{
        total_entities: length(entities_with_health),
        health_breakdown: health_counts,
        interactions_this_week: interactions_count,
        average_health_score: calculate_average_score(entities_with_health)
      },
      top_interactions: top_interactions,
      needs_attention: needs_attention
    }
  end

  defp calculate_average_score([]), do: 0
  defp calculate_average_score(entities_with_health) do
    total = Enum.reduce(entities_with_health, 0, fn %{health: h}, acc -> acc + h.score end)
    round(total / length(entities_with_health))
  end

  defp suggest_action(%{days_since_interaction: days, status: status}) do
    cond do
      status == "critical" and days > 60 ->
        "It's been a while! Consider reaching out to reconnect."
      status == "critical" ->
        "Send a quick check-in message or schedule a call."
      status == "warning" ->
        "Consider dropping a quick note or message."
      true ->
        "Relationship is healthy!"
    end
  end

  @doc """
  Create a health alert reminder for an entity that needs attention.
  """
  def create_health_alert(user_id, entity_id) do
    entity = Repo.get!(Entity, entity_id)
    relationship = Repo.get_by(Relationship, user_id: user_id, entity_id: entity_id)
    health = calculate_health_score(entity, relationship)

    if health.needs_attention do
      # Check if there's already a pending health alert
      existing = from(r in Reminder,
        where: r.user_id == ^user_id and r.entity_id == ^entity_id,
        where: r.type == "health_alert" and is_nil(r.completed_at)
      )
      |> Repo.exists?()

      if existing do
        {:error, :alert_already_exists}
      else
        attrs = %{
          user_id: user_id,
          entity_id: entity_id,
          type: "health_alert",
          title: "Reconnect with #{entity.name}",
          description: "It's been #{health.days_since_interaction} days since your last interaction. #{suggest_action(health)}",
          due_at: DateTime.add(DateTime.utc_now(), 24 * 3600, :second),  # Due tomorrow
          notification_channels: ["in_app", "email"]
        }

        %Reminder{}
        |> Reminder.changeset(attrs)
        |> Repo.insert()
      end
    else
      {:error, :entity_is_healthy}
    end
  end

  @doc """
  Process all relationships and create health alerts for those needing attention.
  This should be called by a scheduled job.
  """
  def process_health_alerts(user_id) do
    needs_attention = list_entities_needing_attention(user_id, limit: 50)

    results = Enum.map(needs_attention, fn %{entity: entity} ->
      case create_health_alert(user_id, entity.id) do
        {:ok, reminder} -> {:ok, reminder}
        {:error, :alert_already_exists} -> {:skip, entity.id}
        {:error, reason} -> {:error, entity.id, reason}
      end
    end)

    created = Enum.count(results, fn
      {:ok, _} -> true
      _ -> false
    end)

    skipped = Enum.count(results, fn
      {:skip, _} -> true
      _ -> false
    end)

    %{
      processed: length(results),
      created: created,
      skipped: skipped
    }
  end
end
