defmodule Conezia.GiftsTest do
  use Conezia.DataCase

  import Conezia.Factory

  alias Conezia.Gifts
  alias Conezia.Gifts.Gift

  describe "create_gift/1" do
    test "creates a gift with valid attrs" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      attrs = %{
        name: "Kindle Paperwhite",
        status: "idea",
        occasion: "birthday",
        occasion_date: Date.add(Date.utc_today(), 30),
        budget_cents: 14999,
        user_id: user.id,
        entity_id: entity.id
      }

      assert {:ok, %Gift{} = gift} = Gifts.create_gift(attrs)
      assert gift.name == "Kindle Paperwhite"
      assert gift.status == "idea"
      assert gift.occasion == "birthday"
      assert gift.budget_cents == 14999
    end

    test "fails with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Gifts.create_gift(%{})
    end

    test "creates auto-reminder for future occasion date" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      attrs = %{
        name: "Watch",
        status: "idea",
        occasion: "birthday",
        occasion_date: Date.add(Date.utc_today(), 60),
        user_id: user.id,
        entity_id: entity.id
      }

      assert {:ok, %Gift{} = gift} = Gifts.create_gift(attrs)
      assert gift.reminder_id
    end

    test "does not create reminder when no occasion date" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      attrs = %{
        name: "Watch",
        status: "idea",
        occasion: "other",
        user_id: user.id,
        entity_id: entity.id
      }

      assert {:ok, %Gift{} = gift} = Gifts.create_gift(attrs)
      refute gift.reminder_id
    end
  end

  describe "list_gifts/2" do
    test "lists gifts for user" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:gift, user: user, entity: entity)
      insert(:gift, user: user, entity: entity)

      {gifts, _meta} = Gifts.list_gifts(user.id)
      assert length(gifts) == 2
    end

    test "filters by status" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:gift, user: user, entity: entity, status: "idea")
      insert(:gift, user: user, entity: entity, status: "purchased")

      {gifts, _meta} = Gifts.list_gifts(user.id, status: "idea")
      assert length(gifts) == 1
      assert hd(gifts).status == "idea"
    end

    test "filters by entity" do
      user = insert(:user)
      entity1 = insert(:entity, owner: user)
      entity2 = insert(:entity, owner: user)
      insert(:gift, user: user, entity: entity1)
      insert(:gift, user: user, entity: entity2)

      {gifts, _meta} = Gifts.list_gifts(user.id, entity_id: entity1.id)
      assert length(gifts) == 1
    end

    test "filters by occasion" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:gift, user: user, entity: entity, occasion: "birthday")
      insert(:gift, user: user, entity: entity, occasion: "christmas")

      {gifts, _meta} = Gifts.list_gifts(user.id, occasion: "christmas")
      assert length(gifts) == 1
      assert hd(gifts).occasion == "christmas"
    end

    test "does not return other users' gifts" do
      user1 = insert(:user)
      user2 = insert(:user)
      entity = insert(:entity, owner: user1)
      insert(:gift, user: user1, entity: entity)

      {gifts, _meta} = Gifts.list_gifts(user2.id)
      assert gifts == []
    end
  end

  describe "list_gifts_for_entity/2" do
    test "returns gifts for specific entity" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:gift, user: user, entity: entity)

      gifts = Gifts.list_gifts_for_entity(entity.id, user.id)
      assert length(gifts) == 1
    end
  end

  describe "upcoming_gifts/2" do
    test "returns gifts with future occasion dates" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:gift, user: user, entity: entity, occasion_date: Date.add(Date.utc_today(), 10))
      insert(:gift, user: user, entity: entity, occasion_date: Date.add(Date.utc_today(), -10))

      gifts = Gifts.upcoming_gifts(user.id)
      assert length(gifts) == 1
    end

    test "excludes given gifts" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:gift, user: user, entity: entity, occasion_date: Date.add(Date.utc_today(), 10), status: "given")

      gifts = Gifts.upcoming_gifts(user.id)
      assert gifts == []
    end
  end

  describe "update_gift/2" do
    test "updates gift attributes" do
      gift = insert(:gift)
      assert {:ok, updated} = Gifts.update_gift(gift, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end
  end

  describe "update_gift_status/2" do
    test "updates status to purchased" do
      gift = insert(:gift, status: "idea")
      assert {:ok, updated} = Gifts.update_gift_status(gift, "purchased")
      assert updated.status == "purchased"
    end

    test "sets given_at when marking as given" do
      gift = insert(:gift, status: "purchased")
      assert {:ok, updated} = Gifts.update_gift_status(gift, "given")
      assert updated.status == "given"
      assert updated.given_at
    end
  end

  describe "delete_gift/1" do
    test "deletes a gift" do
      gift = insert(:gift)
      assert {:ok, _} = Gifts.delete_gift(gift)
      assert is_nil(Gifts.get_gift_for_user(gift.id, gift.user_id))
    end
  end

  describe "budget_summary/2" do
    test "returns budget totals for current year" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      insert(:gift,
        user: user,
        entity: entity,
        budget_cents: 5000,
        actual_cost_cents: 4500,
        status: "purchased",
        occasion_date: Date.utc_today()
      )

      insert(:gift,
        user: user,
        entity: entity,
        budget_cents: 3000,
        actual_cost_cents: 2800,
        status: "given",
        occasion_date: Date.utc_today()
      )

      summary = Gifts.budget_summary(user.id)
      assert summary.total_budget == 8000
      assert summary.total_spent == 7300
    end

    test "returns zeros when no gifts" do
      user = insert(:user)
      summary = Gifts.budget_summary(user.id)
      assert summary.total_budget == 0
      assert summary.total_spent == 0
    end
  end
end
