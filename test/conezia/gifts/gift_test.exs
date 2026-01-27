defmodule Conezia.Gifts.GiftTest do
  use Conezia.DataCase

  import Conezia.Factory
  import Ecto.Changeset

  alias Conezia.Gifts.Gift

  describe "changeset/2" do
    test "valid changeset with required fields" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      changeset = Gift.changeset(%Gift{}, %{
        name: "Book",
        status: "idea",
        occasion: "birthday",
        user_id: user.id,
        entity_id: entity.id
      })

      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = Gift.changeset(%Gift{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).occasion
    end

    test "invalid status" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      changeset = Gift.changeset(%Gift{}, %{
        name: "Book",
        status: "invalid_status",
        occasion: "birthday",
        user_id: user.id,
        entity_id: entity.id
      })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "invalid occasion" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      changeset = Gift.changeset(%Gift{}, %{
        name: "Book",
        status: "idea",
        occasion: "invalid_occasion",
        user_id: user.id,
        entity_id: entity.id
      })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).occasion
    end

    test "validates budget is non-negative" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      changeset = Gift.changeset(%Gift{}, %{
        name: "Book",
        status: "idea",
        occasion: "birthday",
        user_id: user.id,
        entity_id: entity.id,
        budget_cents: -100
      })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).budget_cents
    end

    test "validates URL format" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      changeset = Gift.changeset(%Gift{}, %{
        name: "Book",
        status: "idea",
        occasion: "birthday",
        user_id: user.id,
        entity_id: entity.id,
        url: "not-a-url"
      })

      refute changeset.valid?
      assert "must be a valid URL" in errors_on(changeset).url
    end

    test "accepts valid URL" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      changeset = Gift.changeset(%Gift{}, %{
        name: "Book",
        status: "idea",
        occasion: "birthday",
        user_id: user.id,
        entity_id: entity.id,
        url: "https://amazon.com/product/123"
      })

      assert changeset.valid?
    end

    test "all valid statuses accepted" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      for status <- ~w(idea purchased wrapped given) do
        changeset = Gift.changeset(%Gift{}, %{
          name: "Book",
          status: status,
          occasion: "birthday",
          user_id: user.id,
          entity_id: entity.id
        })

        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "all valid occasions accepted" do
      user = insert(:user)
      entity = insert(:entity, owner: user)

      for occasion <- ~w(birthday christmas holiday anniversary graduation wedding baby_shower housewarming other) do
        changeset = Gift.changeset(%Gift{}, %{
          name: "Book",
          status: "idea",
          occasion: occasion,
          user_id: user.id,
          entity_id: entity.id
        })

        assert changeset.valid?, "Expected occasion '#{occasion}' to be valid"
      end
    end
  end

  describe "status_changeset/2" do
    test "sets given_at when status changes to given" do
      gift = insert(:gift)
      changeset = Gift.status_changeset(gift, "given")
      assert changeset.valid?
      assert get_change(changeset, :given_at)
    end

    test "does not set given_at for other statuses" do
      gift = insert(:gift)
      changeset = Gift.status_changeset(gift, "purchased")
      assert changeset.valid?
      refute get_change(changeset, :given_at)
    end

    test "rejects invalid status" do
      gift = insert(:gift)
      changeset = Gift.status_changeset(gift, "invalid")
      refute changeset.valid?
    end
  end
end
