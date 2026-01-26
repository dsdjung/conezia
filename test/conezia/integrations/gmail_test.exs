defmodule Conezia.Integrations.GmailTest do
  use Conezia.DataCase, async: false

  alias Conezia.Integrations.Gmail

  import Conezia.Factory

  describe "has_gmail_access?/1" do
    test "returns false when user has no connected Google account" do
      user = insert(:user)
      refute Gmail.has_gmail_access?(user.id)
    end

    test "returns true when user has connected Google account" do
      user = insert(:user)
      insert(:external_account, user: user, service_name: "google", status: "connected")

      assert Gmail.has_gmail_access?(user.id)
    end

    test "returns true when user has google_contacts account (backwards compat)" do
      user = insert(:user)
      insert(:external_account, user: user, service_name: "google_contacts", status: "connected")

      assert Gmail.has_gmail_access?(user.id)
    end
  end

  describe "get_last_email_with_contact/2" do
    test "returns error when user has no Google account" do
      user = insert(:user)

      assert {:error, :no_google_account} =
               Gmail.get_last_email_with_contact(user.id, "test@example.com")
    end
  end

  describe "get_last_emails_with_contacts/2" do
    test "returns error when user has no Google account" do
      user = insert(:user)

      assert {:error, :no_google_account} =
               Gmail.get_last_emails_with_contacts(user.id, ["test@example.com"])
    end
  end
end
