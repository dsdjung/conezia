defmodule Conezia.Validators.PlatformValidatorTest do
  use ExUnit.Case, async: true

  alias Conezia.Validators.PlatformValidator

  describe "SSRF protection in validate_webhook_url/1" do
    defp build_changeset(url) do
      %{}
      |> Ecto.Changeset.cast(%{url: url, events: ["entity.created"]}, [:url, :events])
      |> PlatformValidator.validate_webhook_url()
    end

    test "accepts valid external HTTPS URLs" do
      changeset = build_changeset("https://example.com/webhook")
      refute changeset.errors[:url]
    end

    test "rejects HTTP URLs" do
      changeset = build_changeset("http://example.com/webhook")
      assert changeset.errors[:url]
    end

    test "rejects localhost URLs" do
      changeset = build_changeset("https://localhost/webhook")
      assert {"localhost URLs are not allowed", _} = changeset.errors[:url]
    end

    test "rejects localhost.localdomain URLs" do
      changeset = build_changeset("https://localhost.localdomain/webhook")
      assert {"localhost URLs are not allowed", _} = changeset.errors[:url]
    end

    test "rejects loopback IP addresses" do
      changeset = build_changeset("https://127.0.0.1/webhook")
      assert {"private IP addresses are not allowed", _} = changeset.errors[:url]
    end

    test "rejects private Class A IP addresses" do
      changeset = build_changeset("https://10.0.0.1/webhook")
      assert {"private IP addresses are not allowed", _} = changeset.errors[:url]
    end

    test "rejects private Class B IP addresses" do
      changeset = build_changeset("https://172.16.0.1/webhook")
      assert {"private IP addresses are not allowed", _} = changeset.errors[:url]
    end

    test "rejects private Class C IP addresses" do
      changeset = build_changeset("https://192.168.1.1/webhook")
      assert {"private IP addresses are not allowed", _} = changeset.errors[:url]
    end

    test "rejects link-local IP addresses" do
      changeset = build_changeset("https://169.254.1.1/webhook")
      assert {"private IP addresses are not allowed", _} = changeset.errors[:url]
    end

    test "rejects AWS metadata endpoint IP" do
      changeset = build_changeset("https://169.254.169.254/latest/meta-data/")
      assert changeset.errors[:url]
    end

    test "rejects GCP metadata hostnames" do
      changeset = build_changeset("https://metadata.google.internal/computeMetadata/v1/")
      assert {"cloud metadata endpoints are not allowed", _} = changeset.errors[:url]
    end

    test "rejects URLs containing 'metadata' in hostname" do
      changeset = build_changeset("https://my-metadata-server.internal/")
      assert {"cloud metadata endpoints are not allowed", _} = changeset.errors[:url]
    end
  end

  describe "validate_webhook_events/1" do
    defp build_events_changeset(events) do
      %{}
      |> Ecto.Changeset.cast(%{url: "https://example.com", events: events}, [:url, :events])
      |> PlatformValidator.validate_webhook_events()
    end

    test "accepts valid events" do
      changeset = build_events_changeset(["entity.created", "entity.updated"])
      refute changeset.errors[:events]
    end

    test "rejects empty events list" do
      changeset = build_events_changeset([])
      assert {"must have at least one event", _} = changeset.errors[:events]
    end

    test "rejects invalid events" do
      changeset = build_events_changeset(["entity.created", "invalid.event"])
      assert {msg, _} = changeset.errors[:events]
      assert String.contains?(msg, "invalid.event")
    end
  end
end
