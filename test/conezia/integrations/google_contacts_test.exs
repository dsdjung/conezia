defmodule Conezia.Integrations.Providers.GoogleContactsTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.Providers.GoogleContacts

  describe "service_name/0" do
    test "returns 'google_contacts'" do
      assert GoogleContacts.service_name() == "google_contacts"
    end
  end

  describe "display_name/0" do
    test "returns 'Google Contacts'" do
      assert GoogleContacts.display_name() == "Google Contacts"
    end
  end

  describe "icon/0" do
    test "returns hero icon class" do
      assert GoogleContacts.icon() == "hero-user-group"
    end
  end

  describe "scopes/0" do
    test "returns contacts.readonly scope" do
      scopes = GoogleContacts.scopes()
      assert is_list(scopes)
      assert "https://www.googleapis.com/auth/contacts.readonly" in scopes
    end
  end

  describe "authorize_url/2" do
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

    test "generates valid authorization URL" do
      redirect_uri = "https://example.com/callback"
      state = "test_state_123"

      url = GoogleContacts.authorize_url(redirect_uri, state)

      assert String.starts_with?(url, "https://accounts.google.com/o/oauth2/v2/auth?")
      assert String.contains?(url, "client_id=test_client_id")
      assert String.contains?(url, URI.encode_www_form(redirect_uri))
      assert String.contains?(url, "state=test_state_123")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "access_type=offline")
    end
  end
end
