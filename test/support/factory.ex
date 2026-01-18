defmodule Conezia.Factory do
  @moduledoc """
  Factory module for generating test data.
  """
  use ExMachina.Ecto, repo: Conezia.Repo

  alias Conezia.Accounts.{User, AuthProvider, UserToken}
  alias Conezia.Entities.{Entity, Relationship, Identifier, Tag, Group}
  alias Conezia.Interactions.Interaction
  alias Conezia.Communications.{Conversation, Communication}
  alias Conezia.Reminders.Reminder
  alias Conezia.Attachments.Attachment
  alias Conezia.ExternalAccounts.ExternalAccount
  alias Conezia.Imports.ImportJob
  alias Conezia.Platform.{Application, ApplicationUser, Webhook, WebhookDelivery}

  # User factories

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: sequence(:name, &"User #{&1}"),
      hashed_password: Argon2.hash_pwd_salt("Password123"),
      timezone: "UTC",
      tier: "free",
      settings: %{},
      notification_preferences: %{
        "email" => true,
        "push" => true,
        "in_app" => true
      },
      onboarding_state: %{}
    }
  end

  def confirmed_user_factory do
    build(:user, confirmed_at: DateTime.utc_now())
  end

  def auth_provider_factory do
    %AuthProvider{
      provider: sequence(:provider, ["google", "github", "apple"]),
      provider_uid: sequence(:provider_uid, &"uid_#{&1}"),
      user: build(:user)
    }
  end

  def user_token_factory do
    %UserToken{
      token: :crypto.strong_rand_bytes(32),
      context: "session",
      user: build(:user)
    }
  end

  # Entity factories

  def entity_factory do
    %Entity{
      name: sequence(:entity_name, &"Entity #{&1}"),
      type: "person",
      description: "A test entity",
      metadata: %{},
      owner: build(:user)
    }
  end

  def organization_entity_factory do
    build(:entity, type: "organization", name: sequence(:org_name, &"Org #{&1}"))
  end

  def relationship_factory do
    %Relationship{
      type: "friend",
      strength: 50,
      status: "active",
      health_threshold_days: 30,
      user: build(:user),
      entity: build(:entity)
    }
  end

  def identifier_factory do
    %Identifier{
      type: "email",
      value: sequence(:identifier_value, &"contact#{&1}@example.com"),
      is_primary: true,
      entity: build(:entity)
    }
  end

  def tag_factory do
    %Tag{
      name: sequence(:tag_name, &"tag-#{&1}"),
      color: "#3B82F6",
      user: build(:user)
    }
  end

  def group_factory do
    %Group{
      name: sequence(:group_name, &"Group #{&1}"),
      description: "A test group",
      is_smart: false,
      rules: %{},
      user: build(:user)
    }
  end

  def smart_group_factory do
    build(:group, is_smart: true, rules: %{"type" => "person"})
  end

  # Interaction factories

  def interaction_factory do
    %Interaction{
      type: "meeting",
      title: sequence(:interaction_title, &"Meeting #{&1}"),
      content: "Discussed various topics",
      occurred_at: DateTime.utc_now(),
      entity: build(:entity),
      user: build(:user)
    }
  end

  # Communication factories

  def conversation_factory do
    %Conversation{
      channel: "email",
      is_archived: false,
      user: build(:user),
      entity: build(:entity)
    }
  end

  def communication_factory do
    user = build(:user)
    entity = build(:entity, owner: user)
    %Communication{
      direction: "inbound",
      channel: "email",
      content: "This is the email content.",
      sent_at: DateTime.utc_now(),
      entity: entity,
      user: user,
      conversation: build(:conversation, user: user, entity: entity)
    }
  end

  # Reminder factories

  def reminder_factory do
    %Reminder{
      type: "follow_up",
      title: sequence(:reminder_title, &"Reminder #{&1}"),
      description: "Don't forget to follow up",
      due_at: DateTime.add(DateTime.utc_now(), 86400, :second),
      user: build(:user),
      entity: build(:entity)
    }
  end

  # Attachment factories

  def attachment_factory do
    %Attachment{
      filename: sequence(:filename, &"file#{&1}.txt"),
      mime_type: "text/plain",
      size_bytes: 1024,
      storage_key: sequence(:storage_key, &"uploads/#{&1}/file.txt"),
      user: build(:user)
    }
  end

  # External Account factories

  def external_account_factory do
    %ExternalAccount{
      service_name: "google_contacts",
      account_identifier: sequence(:account_id, &"account#{&1}@gmail.com"),
      status: "connected",
      scopes: ["contacts.readonly"],
      user: build(:user)
    }
  end

  # Import Job factories

  def import_job_factory do
    %ImportJob{
      source: "csv",
      status: "pending",
      total_records: 0,
      processed_records: 0,
      user: build(:user)
    }
  end

  # Platform factories

  def application_factory do
    %Application{
      name: sequence(:app_name, &"App #{&1}"),
      description: "A test application",
      callback_urls: ["https://example.com/callback"],
      scopes: ["read:entities", "write:entities"],
      status: "approved",
      developer: build(:user)
    }
  end

  def application_user_factory do
    %ApplicationUser{
      granted_scopes: ["read:entities"],
      application: build(:application),
      user: build(:user)
    }
  end

  def webhook_factory do
    %Webhook{
      url: sequence(:webhook_url, &"https://example.com/webhooks/#{&1}"),
      events: ["entity.created", "entity.updated"],
      status: "active",
      application: build(:application)
    }
  end

  def webhook_delivery_factory do
    %WebhookDelivery{
      event_type: "entity.created",
      payload: %{entity_id: UUID.uuid4()},
      webhook: build(:webhook)
    }
  end
end
