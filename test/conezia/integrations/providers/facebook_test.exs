defmodule Conezia.Integrations.Providers.FacebookTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.Providers.Facebook

  describe "service metadata" do
    test "service_name returns 'facebook'" do
      assert Facebook.service_name() == "facebook"
    end

    test "display_name returns 'Facebook'" do
      assert Facebook.display_name() == "Facebook"
    end

    test "icon returns user-group icon class" do
      assert Facebook.icon() == "hero-user-group"
    end

    test "scopes includes required Facebook permissions" do
      scopes = Facebook.scopes()
      assert is_list(scopes)
      assert "public_profile" in scopes
      assert "email" in scopes
      assert "user_friends" in scopes
    end
  end

  describe "authorize_url/2" do
    setup do
      # Set up test config
      original_config = Application.get_env(:conezia, :facebook_oauth)

      Application.put_env(:conezia, :facebook_oauth,
        client_id: "test_fb_client_id",
        client_secret: "test_fb_client_secret"
      )

      on_exit(fn ->
        if original_config do
          Application.put_env(:conezia, :facebook_oauth, original_config)
        else
          Application.delete_env(:conezia, :facebook_oauth)
        end
      end)

      :ok
    end

    test "generates valid authorization URL" do
      url = Facebook.authorize_url("http://localhost/callback", "test_state")

      assert String.starts_with?(url, "https://www.facebook.com/v19.0/dialog/oauth?")
      assert String.contains?(url, "client_id=test_fb_client_id")
      assert String.contains?(url, "redirect_uri=http")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "state=test_state")
      assert String.contains?(url, "scope=public_profile")
    end
  end

  describe "behaviour implementation" do
    test "implements ServiceProvider behaviour" do
      behaviours = Facebook.__info__(:attributes)[:behaviour] || []
      assert Conezia.Integrations.ServiceProvider in behaviours
    end
  end
end
