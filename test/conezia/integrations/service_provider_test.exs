defmodule Conezia.Integrations.ServiceProviderTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.ServiceProvider

  describe "get_provider/1" do
    test "returns Google Contacts provider for 'google_contacts'" do
      assert {:ok, provider} = ServiceProvider.get_provider("google_contacts")
      assert provider == Conezia.Integrations.Providers.GoogleContacts
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

    test "includes google_contacts as available" do
      providers = ServiceProvider.available_providers()
      google = Enum.find(providers, &(&1.service == "google_contacts"))

      assert google != nil
      assert google.status == :available
      assert google.display_name == "Google Contacts"
    end

    test "includes coming_soon services" do
      providers = ServiceProvider.available_providers()
      coming_soon = Enum.filter(providers, &(&1.status == :coming_soon))

      assert length(coming_soon) > 0
    end
  end
end
