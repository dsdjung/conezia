defmodule Conezia.Workers.GmailSyncWorkerTest do
  use Conezia.DataCase, async: false
  use Oban.Testing, repo: Conezia.Repo

  alias Conezia.Workers.GmailSyncWorker

  import Conezia.Factory

  describe "perform/1" do
    test "returns error when external account not found" do
      user = insert(:user)

      assert {:error, :external_account_not_found} =
               perform_job(GmailSyncWorker, %{
                 "external_account_id" => Ecto.UUID.generate(),
                 "user_id" => user.id
               })
    end

    test "returns error when user_id doesn't match" do
      user1 = insert(:user)
      user2 = insert(:user)
      account = insert(:external_account, user: user1, service_name: "google")

      assert {:error, :unauthorized} =
               perform_job(GmailSyncWorker, %{
                 "external_account_id" => account.id,
                 "user_id" => user2.id
               })
    end
  end

  describe "topic/1" do
    test "returns correct topic format" do
      user_id = Ecto.UUID.generate()
      assert GmailSyncWorker.topic(user_id) == "gmail_sync:#{user_id}"
    end
  end
end
