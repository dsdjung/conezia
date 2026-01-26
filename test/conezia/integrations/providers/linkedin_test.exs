defmodule Conezia.Integrations.Providers.LinkedInTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.Providers.LinkedIn

  describe "service_name/0" do
    test "returns linkedin" do
      assert LinkedIn.service_name() == "linkedin"
    end
  end

  describe "display_name/0" do
    test "returns LinkedIn" do
      assert LinkedIn.display_name() == "LinkedIn"
    end
  end

  describe "icon/0" do
    test "returns briefcase icon" do
      assert LinkedIn.icon() == "hero-briefcase"
    end
  end

  describe "scopes/0" do
    test "returns required OpenID Connect scopes" do
      scopes = LinkedIn.scopes()
      assert "openid" in scopes
      assert "profile" in scopes
      assert "email" in scopes
    end
  end

  describe "authorize_url/2" do
    test "raises when not configured" do
      assert_raise RuntimeError, ~r/client_id not configured/, fn ->
        LinkedIn.authorize_url("http://localhost/callback", "test_state")
      end
    end
  end
end
