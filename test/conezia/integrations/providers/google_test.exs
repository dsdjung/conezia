defmodule Conezia.Integrations.Providers.GoogleTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.Providers.Google

  describe "service metadata" do
    test "service_name returns 'google'" do
      assert Google.service_name() == "google"
    end

    test "display_name returns 'Google'" do
      assert Google.display_name() == "Google"
    end

    test "icon returns cloud icon class" do
      assert Google.icon() == "hero-cloud"
    end

    test "scopes includes all required Google API scopes" do
      scopes = Google.scopes()
      assert is_list(scopes)
      assert "https://www.googleapis.com/auth/contacts.readonly" in scopes
      assert "https://www.googleapis.com/auth/calendar.readonly" in scopes
      assert "https://www.googleapis.com/auth/gmail.readonly" in scopes
    end
  end

  describe "authorize_url/2" do
    setup do
      original_config = Application.get_env(:conezia, :google_oauth)

      Application.put_env(:conezia, :google_oauth,
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      )

      on_exit(fn ->
        if original_config do
          Application.put_env(:conezia, :google_oauth, original_config)
        else
          Application.delete_env(:conezia, :google_oauth)
        end
      end)

      :ok
    end

    test "generates valid authorization URL" do
      url = Google.authorize_url("http://localhost/callback", "test_state")

      assert String.starts_with?(url, "https://accounts.google.com/o/oauth2/v2/auth?")
      assert String.contains?(url, "client_id=test_client_id")
      assert String.contains?(url, "redirect_uri=http")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "state=test_state")
      assert String.contains?(url, "access_type=offline")
      assert String.contains?(url, "prompt=consent")
      # Check that all scopes are included
      assert String.contains?(url, "contacts.readonly")
      assert String.contains?(url, "calendar.readonly")
      assert String.contains?(url, "gmail.readonly")
    end
  end

  describe "behaviour implementation" do
    test "implements ServiceProvider behaviour" do
      behaviours = Google.__info__(:attributes)[:behaviour] || []
      assert Conezia.Integrations.ServiceProvider in behaviours
    end
  end
end
