defmodule Conezia.Integrations.ServiceProviderTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.ServiceProvider

  describe "get_provider/1" do
    test "returns Google Contacts provider for 'google_contacts'" do
      assert {:ok, provider} = ServiceProvider.get_provider("google_contacts")
      assert provider == Conezia.Integrations.Providers.GoogleContacts
    end

    test "returns Google Calendar provider for 'google_calendar'" do
      assert {:ok, provider} = ServiceProvider.get_provider("google_calendar")
      assert provider == Conezia.Integrations.Providers.GoogleCalendar
    end

    test "returns LinkedIn provider for 'linkedin'" do
      assert {:ok, provider} = ServiceProvider.get_provider("linkedin")
      assert provider == Conezia.Integrations.Providers.LinkedIn
    end

    test "returns iCloud provider for 'icloud'" do
      assert {:ok, provider} = ServiceProvider.get_provider("icloud")
      assert provider == Conezia.Integrations.Providers.ICloudContacts
    end

    test "returns Facebook provider for 'facebook'" do
      assert {:ok, provider} = ServiceProvider.get_provider("facebook")
      assert provider == Conezia.Integrations.Providers.Facebook
    end

    test "returns Gmail provider for 'gmail'" do
      assert {:ok, provider} = ServiceProvider.get_provider("gmail")
      assert provider == Conezia.Integrations.Providers.Gmail
    end

    test "returns error for unknown service" do
      assert {:error, "Unknown service: unknown_service"} = ServiceProvider.get_provider("unknown_service")
    end
  end

  describe "available_providers/0" do
    test "returns list of available providers" do
      providers = ServiceProvider.available_providers()

      assert is_list(providers)
      assert length(providers) > 0

      # Check that each provider has required fields
      for provider <- providers do
        assert Map.has_key?(provider, :service)
        assert Map.has_key?(provider, :display_name)
        assert Map.has_key?(provider, :icon)
        assert Map.has_key?(provider, :status)
      end
    end

    test "includes all expected services" do
      providers = ServiceProvider.available_providers()
      services = Enum.map(providers, & &1.service)

      assert "google_contacts" in services
      assert "google_calendar" in services
      assert "gmail" in services
      assert "linkedin" in services
      assert "icloud" in services
      assert "facebook" in services
      assert "outlook" in services
    end

    test "icloud is always available (uses app-specific passwords)" do
      providers = ServiceProvider.available_providers()
      icloud = Enum.find(providers, &(&1.service == "icloud"))

      assert icloud != nil
      assert icloud.status == :available
      assert icloud.display_name == "iCloud Contacts"
    end

    test "includes coming_soon services" do
      providers = ServiceProvider.available_providers()
      coming_soon = Enum.filter(providers, &(&1.status == :coming_soon))

      # At least outlook should be coming_soon
      services = Enum.map(coming_soon, & &1.service)
      assert "outlook" in services
    end
  end
end
