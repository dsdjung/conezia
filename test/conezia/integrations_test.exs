defmodule Conezia.IntegrationsTest do
  use Conezia.DataCase

  import Conezia.Factory

  alias Conezia.Integrations

  describe "list_available_services/1" do
    test "returns all providers with status" do
      user = insert(:user)

      services = Integrations.list_available_services(user.id)

      assert is_list(services)
      # Should have at least the google_contacts provider
      google = Enum.find(services, &(&1.service == "google_contacts"))
      assert google != nil
    end

    test "marks connected services appropriately" do
      # Set up Google OAuth config for this test
      original = Application.get_env(:conezia, :google_oauth)
      Application.put_env(:conezia, :google_oauth, [
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      ])

      on_exit(fn ->
        if original do
          Application.put_env(:conezia, :google_oauth, original)
        else
          Application.delete_env(:conezia, :google_oauth)
        end
      end)

      user = insert(:user)

      # No connected services, so status should be :available
      services = Integrations.list_available_services(user.id)
      google = Enum.find(services, &(&1.service == "google_contacts"))

      assert google.account == nil
      assert google.status == :available
    end
  end

  describe "get_authorize_url/3" do
    setup do
      # Set up test config
      Application.put_env(:conezia, :google_oauth, [
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      ])

      on_exit(fn ->
        Application.put_env(:conezia, :google_oauth, [])
      end)

      :ok
    end

    test "generates valid URL for known service" do
      redirect_uri = "https://example.com/callback"
      state = "test_state"

      assert {:ok, url} = Integrations.get_authorize_url("google_contacts", redirect_uri, state)
      assert String.starts_with?(url, "https://accounts.google.com")
      assert String.contains?(url, "client_id=test_client_id")
    end

    test "returns error for unknown service" do
      assert {:error, _} = Integrations.get_authorize_url("unknown", "https://example.com", "state")
    end
  end

  describe "list_import_jobs/2" do
    test "returns empty list when no jobs exist" do
      user = insert(:user)

      jobs = Integrations.list_import_jobs(user.id)
      assert jobs == []
    end

    test "returns jobs for user" do
      user = insert(:user)
      _job = insert(:import_job, user: user, source: "google")

      jobs = Integrations.list_import_jobs(user.id)
      assert length(jobs) == 1
    end

    test "respects limit option" do
      user = insert(:user)
      for _ <- 1..5, do: insert(:import_job, user: user, source: "google")

      jobs = Integrations.list_import_jobs(user.id, limit: 2)
      assert length(jobs) == 2
    end

    test "does not return other users' jobs" do
      user1 = insert(:user)
      user2 = insert(:user)
      _job = insert(:import_job, user: user1, source: "google")

      jobs = Integrations.list_import_jobs(user2.id)
      assert jobs == []
    end
  end
end
