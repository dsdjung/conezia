defmodule Conezia.HealthTest do
  use Conezia.DataCase, async: true

  alias Conezia.Health
  alias Conezia.Entities.{Entity, Relationship}

  describe "calculate_health_score/2" do
    test "returns healthy status for recent interaction" do
      entity = %Entity{
        last_interaction_at: DateTime.utc_now()
      }

      health = Health.calculate_health_score(entity)

      assert health.status == "healthy"
      assert health.score >= 80
      assert health.needs_attention == false
      assert health.days_since_interaction == 0
    end

    test "returns warning status when approaching threshold" do
      # 20 days ago with 30 day threshold = 67% through threshold
      last_interaction = DateTime.add(DateTime.utc_now(), -20 * 86400, :second)
      entity = %Entity{last_interaction_at: last_interaction}

      health = Health.calculate_health_score(entity)

      assert health.status == "warning"
      assert health.score >= 50 and health.score < 80
      assert health.needs_attention == true
    end

    test "returns critical status when past threshold" do
      # 45 days ago with 30 day threshold = past threshold
      last_interaction = DateTime.add(DateTime.utc_now(), -45 * 86400, :second)
      entity = %Entity{last_interaction_at: last_interaction}

      health = Health.calculate_health_score(entity)

      assert health.status == "critical"
      assert health.score < 50
      assert health.needs_attention == true
    end

    test "uses relationship threshold when provided" do
      # 20 days ago with 60 day threshold = 33% through threshold (healthy)
      last_interaction = DateTime.add(DateTime.utc_now(), -20 * 86400, :second)
      entity = %Entity{last_interaction_at: last_interaction}
      relationship = %Relationship{health_threshold_days: 60}

      health = Health.calculate_health_score(entity, relationship)

      assert health.status == "healthy"
      assert health.threshold_days == 60
    end

    test "handles nil last_interaction_at" do
      entity = %Entity{last_interaction_at: nil}

      health = Health.calculate_health_score(entity)

      assert health.status == "critical"
      assert health.days_since_interaction == 999
      assert health.needs_attention == true
    end

    test "calculates days_remaining correctly" do
      # 10 days ago with 30 day threshold = 20 days remaining
      last_interaction = DateTime.add(DateTime.utc_now(), -10 * 86400, :second)
      entity = %Entity{last_interaction_at: last_interaction}

      health = Health.calculate_health_score(entity)

      assert health.days_remaining == 20
      assert health.days_since_interaction == 10
    end
  end

  describe "list_entities_needing_attention/2" do
    setup do
      user = insert(:confirmed_user)
      {:ok, user: user}
    end

    test "returns entities with warning or critical health", %{user: user} do
      # Create an entity with old interaction
      old_entity = insert(:entity, owner: user, last_interaction_at: DateTime.add(DateTime.utc_now(), -45 * 86400, :second))
      insert(:relationship, user: user, entity: old_entity, status: "active")

      # Create an entity with recent interaction
      recent_entity = insert(:entity, owner: user, last_interaction_at: DateTime.utc_now())
      insert(:relationship, user: user, entity: recent_entity, status: "active")

      results = Health.list_entities_needing_attention(user.id)

      # Only the old entity should need attention
      entity_ids = Enum.map(results, fn %{entity: e} -> e.id end)
      assert old_entity.id in entity_ids
      refute recent_entity.id in entity_ids
    end

    test "limits results", %{user: user} do
      # Create multiple entities with old interactions
      for _ <- 1..5 do
        entity = insert(:entity, owner: user, last_interaction_at: DateTime.add(DateTime.utc_now(), -45 * 86400, :second))
        insert(:relationship, user: user, entity: entity, status: "active")
      end

      results = Health.list_entities_needing_attention(user.id, limit: 3)

      assert length(results) == 3
    end

    test "sorts by health score ascending (worst first)", %{user: user} do
      # Create entities with different interaction ages
      entity_45_days = insert(:entity, owner: user, last_interaction_at: DateTime.add(DateTime.utc_now(), -45 * 86400, :second))
      insert(:relationship, user: user, entity: entity_45_days, status: "active")

      entity_60_days = insert(:entity, owner: user, last_interaction_at: DateTime.add(DateTime.utc_now(), -60 * 86400, :second))
      insert(:relationship, user: user, entity: entity_60_days, status: "active")

      results = Health.list_entities_needing_attention(user.id)

      # 60 day old should be first (lower score)
      first_entity_id = hd(results).entity.id
      assert first_entity_id == entity_60_days.id
    end
  end

  describe "generate_weekly_digest/1" do
    setup do
      user = insert(:confirmed_user)
      {:ok, user: user}
    end

    test "returns digest structure", %{user: user} do
      digest = Health.generate_weekly_digest(user.id)

      assert Map.has_key?(digest, :period)
      assert Map.has_key?(digest, :summary)
      assert Map.has_key?(digest, :top_interactions)
      assert Map.has_key?(digest, :needs_attention)

      assert Map.has_key?(digest.summary, :total_entities)
      assert Map.has_key?(digest.summary, :health_breakdown)
      assert Map.has_key?(digest.summary, :interactions_this_week)
      assert Map.has_key?(digest.summary, :average_health_score)
    end

    test "includes period dates", %{user: user} do
      digest = Health.generate_weekly_digest(user.id)

      assert %{start_date: start_date, end_date: end_date} = digest.period
      assert Date.diff(end_date, start_date) == 7
    end

    test "counts health breakdown", %{user: user} do
      # Create healthy entity
      healthy_entity = insert(:entity, owner: user, last_interaction_at: DateTime.utc_now())
      insert(:relationship, user: user, entity: healthy_entity, status: "active")

      # Create critical entity
      critical_entity = insert(:entity, owner: user, last_interaction_at: DateTime.add(DateTime.utc_now(), -45 * 86400, :second))
      insert(:relationship, user: user, entity: critical_entity, status: "active")

      digest = Health.generate_weekly_digest(user.id)

      assert digest.summary.health_breakdown.healthy >= 1
      assert digest.summary.health_breakdown.critical >= 1
    end
  end
end
