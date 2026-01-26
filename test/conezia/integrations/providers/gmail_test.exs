defmodule Conezia.Integrations.Providers.GmailTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.Providers.Gmail

  describe "service metadata" do
    test "service_name returns 'gmail'" do
      assert Gmail.service_name() == "gmail"
    end

    test "display_name returns 'Gmail'" do
      assert Gmail.display_name() == "Gmail"
    end

    test "icon returns envelope icon class" do
      assert Gmail.icon() == "hero-envelope"
    end

    test "scopes includes gmail readonly scope" do
      scopes = Gmail.scopes()
      assert is_list(scopes)
      assert "https://www.googleapis.com/auth/gmail.readonly" in scopes
    end
  end

  describe "authorize_url/2" do
    setup do
      # Set up test config
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
      url = Gmail.authorize_url("http://localhost/callback", "test_state")

      assert String.starts_with?(url, "https://accounts.google.com/o/oauth2/v2/auth?")
      assert String.contains?(url, "client_id=test_client_id")
      assert String.contains?(url, "redirect_uri=http")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "state=test_state")
      assert String.contains?(url, "access_type=offline")
      assert String.contains?(url, "prompt=consent")
      assert String.contains?(url, "gmail.readonly")
    end
  end

  describe "behaviour implementation" do
    test "implements ServiceProvider behaviour" do
      behaviours = Gmail.__info__(:attributes)[:behaviour] || []
      assert Conezia.Integrations.ServiceProvider in behaviours
    end
  end
end
