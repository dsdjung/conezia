defmodule Conezia.Integrations.Providers.ICloudContactsTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.Providers.ICloudContacts

  describe "service metadata" do
    test "service_name returns 'icloud'" do
      assert ICloudContacts.service_name() == "icloud"
    end

    test "display_name returns 'iCloud Contacts'" do
      assert ICloudContacts.display_name() == "iCloud Contacts"
    end

    test "icon returns cloud icon class" do
      assert ICloudContacts.icon() == "hero-cloud"
    end

    test "scopes returns contacts scope" do
      scopes = ICloudContacts.scopes()
      assert is_list(scopes)
      assert "contacts" in scopes
    end
  end

  describe "authorize_url/2" do
    test "returns special icloud:// URL for credential entry" do
      url = ICloudContacts.authorize_url("http://localhost/callback", "test_state")
      assert url == "icloud://auth"
    end
  end

  describe "exchange_code/2" do
    test "returns error for invalid JSON" do
      assert {:error, "Invalid credentials format - expected JSON"} =
               ICloudContacts.exchange_code("not json", "http://localhost/callback")
    end

    test "returns error for missing apple_id" do
      json = Jason.encode!(%{"app_password" => "xxxx-xxxx-xxxx-xxxx"})

      assert {:error, "Invalid credentials format - expected apple_id and app_password"} =
               ICloudContacts.exchange_code(json, "http://localhost/callback")
    end

    test "returns error for missing app_password" do
      json = Jason.encode!(%{"apple_id" => "user@icloud.com"})

      assert {:error, "Invalid credentials format - expected apple_id and app_password"} =
               ICloudContacts.exchange_code(json, "http://localhost/callback")
    end
  end

  describe "refresh_token/1" do
    test "returns error since app-specific passwords don't refresh" do
      assert {:error, message} = ICloudContacts.refresh_token("user@icloud.com")
      assert String.contains?(message, "don't need refreshing")
    end
  end

  describe "revoke_access/1" do
    test "returns :ok since app-specific passwords can't be revoked programmatically" do
      assert :ok = ICloudContacts.revoke_access("test_token")
    end
  end

  describe "behaviour implementation" do
    test "implements ServiceProvider behaviour" do
      behaviours = ICloudContacts.__info__(:attributes)[:behaviour] || []
      assert Conezia.Integrations.ServiceProvider in behaviours
    end
  end
end
