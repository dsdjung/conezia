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

  describe "contact deduplication" do
    # Note: These tests verify the internal deduplication logic through the module's
    # private functions. We test the behavior indirectly through fetch_contacts
    # or expose the function for testing.

    test "contact_completeness_score prefers longer names" do
      # "David Oh" should score higher than "Oh" for name completeness
      david_oh = %{
        name: "David Oh",
        email: "david@example.com",
        phone: nil,
        organization: nil,
        metadata: %{source: "gmail"}
      }

      oh = %{
        name: "Oh",
        email: "david@example.com",
        phone: nil,
        organization: nil,
        metadata: %{source: "google_contacts"}
      }

      # Call the private function through send
      david_score = call_private(:contact_completeness_score, [david_oh])
      oh_score = call_private(:contact_completeness_score, [oh])

      assert david_score > oh_score, "David Oh (#{david_score}) should score higher than Oh (#{oh_score})"
    end

    test "contact_completeness_score prefers multi-part names" do
      full_name = %{
        name: "John Smith",
        email: "john@example.com",
        phone: nil,
        organization: nil,
        metadata: %{source: "gmail"}
      }

      single_name = %{
        name: "John",
        email: "john@example.com",
        phone: nil,
        organization: nil,
        metadata: %{source: "gmail"}
      }

      full_score = call_private(:contact_completeness_score, [full_name])
      single_score = call_private(:contact_completeness_score, [single_name])

      assert full_score > single_score
    end

    test "find_best_name returns longest/most complete name" do
      contacts = [
        %{name: "Oh"},
        %{name: "David Oh"},
        %{name: "D Oh"}
      ]

      best = call_private(:find_best_name, [contacts])
      assert best == "David Oh"
    end

    test "find_best_name returns nil for empty list" do
      assert call_private(:find_best_name, [[]]) == nil
    end

    test "find_best_name prefers more name parts over length" do
      contacts = [
        %{name: "Jonathan"},        # 1 part, 8 chars
        %{name: "Jo Kim"}           # 2 parts, 6 chars
      ]

      best = call_private(:find_best_name, [contacts])
      assert best == "Jo Kim"
    end
  end

  # Helper to call private functions for testing
  defp call_private(func, args) do
    # Use :erlang.apply with the module and function name as atom
    apply(Google, func, args)
  rescue
    UndefinedFunctionError ->
      # If the function is not exported, we can use Module.concat and Code.eval_string
      # but that's hacky. Instead, let's test through the public interface.
      raise "Cannot test private function #{func} - consider making it public for testing"
  end
end
