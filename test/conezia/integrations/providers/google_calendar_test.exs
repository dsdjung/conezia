defmodule Conezia.Integrations.Providers.GoogleCalendarTest do
  use ExUnit.Case, async: true

  alias Conezia.Integrations.Providers.GoogleCalendar

  describe "service metadata" do
    test "service_name returns 'google_calendar'" do
      assert GoogleCalendar.service_name() == "google_calendar"
    end

    test "display_name returns 'Google Calendar'" do
      assert GoogleCalendar.display_name() == "Google Calendar"
    end

    test "icon returns calendar icon class" do
      assert GoogleCalendar.icon() == "hero-calendar-days"
    end

    test "scopes includes calendar readonly scope" do
      scopes = GoogleCalendar.scopes()
      assert is_list(scopes)
      assert "https://www.googleapis.com/auth/calendar.readonly" in scopes
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
      url = GoogleCalendar.authorize_url("http://localhost/callback", "test_state")

      assert String.starts_with?(url, "https://accounts.google.com/o/oauth2/v2/auth?")
      assert String.contains?(url, "client_id=test_client_id")
      assert String.contains?(url, "redirect_uri=http")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "state=test_state")
      assert String.contains?(url, "access_type=offline")
      assert String.contains?(url, "prompt=consent")
    end
  end

  describe "behaviour implementation" do
    test "implements ServiceProvider behaviour" do
      behaviours = GoogleCalendar.__info__(:attributes)[:behaviour] || []
      assert Conezia.Integrations.ServiceProvider in behaviours
    end
  end
end
