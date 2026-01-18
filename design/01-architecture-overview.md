# Conezia Architecture Overview

## 1. Introduction

This document describes the high-level architecture for Conezia, a personal relationship management platform built with Elixir/Phoenix.

### 1.1 Technology Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Backend Framework** | Elixir/Phoenix 1.7+ | Real-time capabilities (LiveView, Channels), fault tolerance, horizontal scaling |
| **Database** | PostgreSQL 16 | JSONB support, full-text search, row-level security |
| **Cache** | Redis 7 | Session storage, rate limiting, pub/sub for real-time |
| **Search** | PostgreSQL FTS + Elasticsearch (Phase 3) | Start simple, scale to dedicated search |
| **File Storage** | S3-compatible (MinIO local, AWS S3 prod) | Attachments, avatars, exports |
| **Background Jobs** | Oban | Reliable job processing with PostgreSQL backend |
| **Real-time** | Phoenix Channels + LiveView | WebSocket-based real-time updates |
| **Container Runtime** | Docker + Docker Compose | Development parity, easy deployment |

### 1.2 Design Principles

1. **Convention over Configuration**: Follow Phoenix conventions
2. **Contexts for Domain Boundaries**: Separate business logic into contexts
3. **Validate at the Boundary**: All external input validated via Ecto changesets
4. **Fail Fast**: Use pattern matching and guards liberally
5. **Supervision Trees**: Leverage OTP for fault tolerance
6. **Database as Source of Truth**: Avoid distributed state where possible

---

## 2. System Architecture

### 2.1 High-Level Diagram

```
                                    ┌─────────────────────────────────────────┐
                                    │              Load Balancer              │
                                    │            (nginx/Caddy)                │
                                    └─────────────────┬───────────────────────┘
                                                      │
                         ┌────────────────────────────┼────────────────────────────┐
                         │                            │                            │
                         ▼                            ▼                            ▼
              ┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
              │  Phoenix Node 1  │       │  Phoenix Node 2  │       │  Phoenix Node N  │
              │                  │       │                  │       │                  │
              │  ┌────────────┐  │       │  ┌────────────┐  │       │  ┌────────────┐  │
              │  │  Endpoint  │  │       │  │  Endpoint  │  │       │  │  Endpoint  │  │
              │  └─────┬──────┘  │       │  └─────┬──────┘  │       │  └─────┬──────┘  │
              │        │         │       │        │         │       │        │         │
              │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │
              │  │   Router   │  │       │  │   Router   │  │       │  │   Router   │  │
              │  └─────┬──────┘  │       │  └─────┬──────┘  │       │  └─────┬──────┘  │
              │        │         │       │        │         │       │        │         │
              │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │
              │  │ Controllers│  │       │  │ Controllers│  │       │  │ Controllers│  │
              │  │ & LiveView │  │       │  │ & LiveView │  │       │  │ & LiveView │  │
              │  └─────┬──────┘  │       │  └─────┬──────┘  │       │  └─────┬──────┘  │
              │        │         │       │        │         │       │        │         │
              │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │
              │  │  Contexts  │  │       │  │  Contexts  │  │       │  │  Contexts  │  │
              │  └─────┬──────┘  │       │  └─────┬──────┘  │       │  └─────┬──────┘  │
              │        │         │       │        │         │       │        │         │
              │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │       │  ┌─────▼──────┐  │
              │  │    Oban    │  │       │  │    Oban    │  │       │  │    Oban    │  │
              │  └────────────┘  │       │  └────────────┘  │       │  └────────────┘  │
              └────────┬─────────┘       └────────┬─────────┘       └────────┬─────────┘
                       │                          │                          │
                       └──────────────────────────┼──────────────────────────┘
                                                  │
                    ┌─────────────────────────────┼─────────────────────────────┐
                    │                             │                             │
                    ▼                             ▼                             ▼
         ┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
         │   PostgreSQL     │          │      Redis       │          │   S3/MinIO       │
         │   (Primary)      │          │                  │          │                  │
         │                  │          │  - Sessions      │          │  - Attachments   │
         │  - All Data      │          │  - Cache         │          │  - Avatars       │
         │  - Oban Jobs     │          │  - Rate Limits   │          │  - Exports       │
         │  - FTS Index     │          │  - PubSub        │          │                  │
         └────────┬─────────┘          └──────────────────┘          └──────────────────┘
                  │
                  ▼
         ┌──────────────────┐
         │   PostgreSQL     │
         │   (Replica)      │
         │   Read-only      │
         └──────────────────┘
```

### 2.2 Request Flow

```
HTTP Request
     │
     ▼
┌─────────────┐
│  Endpoint   │ ─── Telemetry, Logging, Static Files
└─────┬───────┘
      │
      ▼
┌─────────────┐
│   Router    │ ─── Route matching, Pipeline selection
└─────┬───────┘
      │
      ▼
┌─────────────┐
│  Pipeline   │ ─── Plugs: Auth, Rate Limit, CORS, etc.
└─────┬───────┘
      │
      ▼
┌─────────────┐
│ Controller  │ ─── Request handling, params extraction
└─────┬───────┘
      │
      ▼
┌─────────────┐
│  Context    │ ─── Business logic, authorization
└─────┬───────┘
      │
      ▼
┌─────────────┐
│   Schema    │ ─── Validation via changesets
└─────┬───────┘
      │
      ▼
┌─────────────┐
│    Repo     │ ─── Database operations
└─────────────┘
```

---

## 3. Application Structure

### 3.1 Phoenix Contexts

Contexts encapsulate related functionality and define clear boundaries:

```
lib/conezia/
├── accounts/                    # User account management
│   ├── user.ex                  # User schema
│   ├── auth_provider.ex         # OAuth providers
│   ├── session.ex               # Session management
│   └── accounts.ex              # Context module
│
├── entities/                    # Entity management
│   ├── entity.ex                # Entity schema
│   ├── relationship.ex          # Relationship schema
│   ├── identifier.ex            # Identifier schema
│   ├── tag.ex                   # Tag schema
│   ├── group.ex                 # Group schema
│   └── entities.ex              # Context module
│
├── communications/              # Messaging & communications
│   ├── conversation.ex          # Conversation schema
│   ├── communication.ex         # Message schema
│   ├── channel_adapter.ex       # Channel abstraction
│   └── communications.ex        # Context module
│
├── interactions/                # Notes, meetings, history
│   ├── interaction.ex           # Interaction schema
│   ├── activity_log.ex          # Activity log schema
│   └── interactions.ex          # Context module
│
├── reminders/                   # Reminders & alerts
│   ├── reminder.ex              # Reminder schema
│   ├── health_check.ex          # Relationship health logic
│   └── reminders.ex             # Context module
│
├── imports/                     # Contact import/export
│   ├── import_job.ex            # Import job schema
│   ├── adapters/                # Source-specific adapters
│   │   ├── google_contacts.ex
│   │   ├── csv.ex
│   │   └── vcard.ex
│   └── imports.ex               # Context module
│
├── external_accounts/           # External service connections
│   ├── external_account.ex      # External account schema
│   ├── adapters/                # Service-specific adapters
│   │   ├── google.ex            # Google Contacts/Calendar
│   │   ├── icloud.ex            # iCloud contacts
│   │   ├── outlook.ex           # Microsoft Outlook
│   │   └── linkedin.ex          # LinkedIn connections
│   ├── sync_worker.ex           # Background sync job
│   └── external_accounts.ex     # Context module
│
├── attachments/                 # File management
│   ├── attachment.ex            # Attachment schema
│   ├── storage.ex               # Storage abstraction
│   └── attachments.ex           # Context module
│
├── platform/                    # Third-party app platform
│   ├── application.ex           # App registration schema
│   ├── application_user.ex      # App-user link
│   ├── webhook.ex               # Webhook schema
│   ├── webhook_delivery.ex      # Delivery log
│   └── platform.ex              # Context module
│
├── search/                      # Search functionality
│   ├── indexer.ex               # Search indexing
│   └── search.ex                # Search context
│
└── notifications/               # Notification delivery
    ├── email.ex                 # Email notifications
    ├── push.ex                  # Push notifications
    └── notifications.ex         # Context module
```

### 3.2 Web Layer Structure

```
lib/conezia_web/
├── endpoint.ex                  # Phoenix endpoint
├── router.ex                    # Route definitions
├── telemetry.ex                 # Metrics & monitoring
│
├── plugs/                       # Custom plugs
│   ├── authenticate.ex          # JWT/session auth
│   ├── rate_limit.ex            # Rate limiting
│   ├── api_auth.ex              # API key auth
│   └── current_user.ex          # Load current user
│
├── controllers/                 # REST API controllers
│   ├── api/
│   │   └── v1/
│   │       ├── auth_controller.ex
│   │       ├── user_controller.ex
│   │       ├── entity_controller.ex
│   │       ├── relationship_controller.ex
│   │       ├── communication_controller.ex
│   │       ├── reminder_controller.ex
│   │       ├── import_controller.ex
│   │       ├── search_controller.ex
│   │       └── ...
│   └── fallback_controller.ex   # Error handling
│
├── live/                        # LiveView modules
│   ├── dashboard_live.ex
│   ├── entity_live/
│   │   ├── index.ex
│   │   ├── show.ex
│   │   └── form_component.ex
│   ├── communication_live/
│   └── ...
│
├── channels/                    # WebSocket channels
│   ├── user_socket.ex
│   ├── notification_channel.ex
│   └── presence.ex
│
├── views/                       # JSON views
│   └── api/
│       └── v1/
│           ├── entity_json.ex
│           └── ...
│
└── components/                  # LiveView components
    ├── core_components.ex
    └── ...
```

---

## 4. Context Design

### 4.1 Accounts Context

```elixir
defmodule Conezia.Accounts do
  @moduledoc """
  The Accounts context handles user registration, authentication,
  and profile management.
  """

  # User Management
  def get_user!(id)
  def get_user_by_email(email)
  def register_user(attrs)
  def update_user(user, attrs)
  def delete_user(user)
  def change_user(user, attrs \\ %{})

  # Authentication
  def authenticate_by_email_password(email, password)
  def authenticate_by_oauth(provider, oauth_data)
  def generate_user_session_token(user)
  def get_user_by_session_token(token)
  def delete_session_token(token)

  # Password Reset
  def deliver_password_reset_instructions(user)
  def reset_user_password(user, attrs)

  # Email Verification
  def deliver_email_verification(user)
  def verify_user_email(token)

  # Preferences
  def get_user_preferences(user)
  def update_user_preferences(user, attrs)
  def get_notification_settings(user)
  def update_notification_settings(user, attrs)
end
```

### 4.2 Entities Context

```elixir
defmodule Conezia.Entities do
  @moduledoc """
  The Entities context manages entities, relationships, tags, and groups.
  """

  # Entity CRUD
  def list_entities(user, filters \\ %{})
  def get_entity!(user, id)
  def create_entity(user, attrs)
  def update_entity(entity, attrs)
  def delete_entity(entity)
  def archive_entity(entity)

  # Duplicate Detection
  def find_potential_duplicates(user, attrs)
  def merge_entities(user, source_id, target_id, options \\ [])

  # Relationships
  def list_relationships(user, filters \\ %{})
  def get_relationship!(user, id)
  def create_relationship(user, entity, attrs)
  def update_relationship(relationship, attrs)
  def delete_relationship(relationship)

  # Identifiers
  def add_identifier(entity, attrs)
  def update_identifier(identifier, attrs)
  def delete_identifier(identifier)
  def check_identifier_uniqueness(type, value)

  # Tags
  def list_tags(user)
  def create_tag(user, attrs)
  def update_tag(tag, attrs)
  def delete_tag(tag)
  def add_tags_to_entity(entity, tag_ids)
  def remove_tag_from_entity(entity, tag_id)

  # Groups
  def list_groups(user)
  def get_group!(user, id)
  def create_group(user, attrs)
  def update_group(group, attrs)
  def delete_group(group)
  def add_entities_to_group(group, entity_ids)
  def remove_entity_from_group(group, entity_id)
  def get_smart_group_members(group)
end
```

### 4.3 Communications Context

```elixir
defmodule Conezia.Communications do
  @moduledoc """
  The Communications context handles conversations and messages
  across multiple channels.
  """

  # Conversations
  def list_conversations(user, filters \\ %{})
  def get_conversation!(user, id)
  def create_conversation(user, entity, attrs)
  def update_conversation(conversation, attrs)
  def archive_conversation(conversation)
  def delete_conversation(conversation)

  # Messages
  def list_messages(conversation, pagination \\ %{})
  def send_message(user, conversation, attrs)
  def mark_message_read(message)

  # Channel Integration
  def sync_external_messages(user, channel, since \\ nil)
  def send_via_channel(message, channel)
end
```

### 4.4 Reminders Context

```elixir
defmodule Conezia.Reminders do
  @moduledoc """
  The Reminders context manages reminders, recurring schedules,
  and relationship health monitoring.
  """

  # Reminders
  def list_reminders(user, filters \\ %{})
  def get_reminder!(user, id)
  def create_reminder(user, attrs)
  def update_reminder(reminder, attrs)
  def delete_reminder(reminder)
  def snooze_reminder(reminder, until)
  def complete_reminder(reminder)

  # Due Reminders
  def list_due_reminders(user)
  def list_overdue_reminders(user)
  def process_due_reminders()

  # Relationship Health
  def calculate_health_score(entity)
  def list_entities_needing_attention(user)
  def generate_weekly_digest(user)
  def create_health_alert(user, entity)
end
```

---

## 5. Authentication & Authorization

### 5.1 Authentication Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     Authentication Flows                         │
└─────────────────────────────────────────────────────────────────┘

1. Google OAuth Flow:
   ┌────────┐    ┌─────────┐    ┌────────┐    ┌──────────┐
   │ Client │───▶│ Phoenix │───▶│ Google │───▶│ Callback │
   └────────┘    └─────────┘    └────────┘    └────┬─────┘
                                                   │
                                    ┌──────────────▼──────────────┐
                                    │ Create/Update User          │
                                    │ Generate Session Token      │
                                    │ Set HTTP-only Cookie        │
                                    └─────────────────────────────┘

2. Email/Password Flow:
   ┌────────┐    ┌─────────────┐    ┌──────────────┐
   │ Client │───▶│ POST /login │───▶│ Validate     │
   └────────┘    └─────────────┘    │ Credentials  │
                                    └──────┬───────┘
                                           │
                        ┌──────────────────▼──────────────────┐
                        │ Argon2 Password Verification        │
                        │ Generate Session Token              │
                        │ Return JWT + Set Cookie             │
                        └─────────────────────────────────────┘

3. API Key Flow (Third-party Apps):
   ┌────────┐    ┌─────────────┐    ┌──────────────┐
   │ Client │───▶│ API Request │───▶│ Verify       │
   │        │    │ + API Key   │    │ API Key      │
   └────────┘    └─────────────┘    └──────┬───────┘
                                           │
                        ┌──────────────────▼──────────────────┐
                        │ Load Application                    │
                        │ Verify Scopes                       │
                        │ Set conn.assigns.current_app        │
                        └─────────────────────────────────────┘
```

### 5.2 Authorization

Using a policy-based authorization approach:

```elixir
defmodule Conezia.Policy do
  @moduledoc "Authorization policies for resources"

  def authorize(:entity, :read, user, entity) do
    entity.owner_id == user.id
  end

  def authorize(:entity, :update, user, entity) do
    entity.owner_id == user.id
  end

  def authorize(:entity, :delete, user, entity) do
    entity.owner_id == user.id and not entity.archived_at
  end

  # Team sharing (Phase: Team tier)
  def authorize(:entity, :read, user, entity) do
    entity.owner_id == user.id or
      team_member?(user, entity.owner_id)
  end
end
```

### 5.3 API Scopes

```elixir
@scopes %{
  "read:entities" => "Read entities and relationships",
  "write:entities" => "Create and update entities",
  "delete:entities" => "Delete entities",
  "read:communications" => "Read conversations and messages",
  "write:communications" => "Send messages",
  "read:reminders" => "Read reminders",
  "write:reminders" => "Create and update reminders",
  "read:profile" => "Read user profile",
  "write:profile" => "Update user profile"
}
```

---

## 6. Real-time Architecture

### 6.1 Phoenix Channels

```elixir
# User-specific channel for notifications
defmodule ConeziaWeb.NotificationChannel do
  use ConeziaWeb, :channel

  def join("notifications:" <> user_id, _params, socket) do
    if socket.assigns.user_id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Broadcast reminder due
  def broadcast_reminder_due(user_id, reminder) do
    ConeziaWeb.Endpoint.broadcast(
      "notifications:#{user_id}",
      "reminder:due",
      %{reminder: reminder}
    )
  end

  # Broadcast new message
  def broadcast_new_message(user_id, message) do
    ConeziaWeb.Endpoint.broadcast(
      "notifications:#{user_id}",
      "message:new",
      %{message: message}
    )
  end
end
```

### 6.2 PubSub via Redis

```elixir
# config/config.exs
config :conezia, ConeziaWeb.Endpoint,
  pubsub_server: Conezia.PubSub

config :conezia, Conezia.PubSub,
  adapter: Phoenix.PubSub.Redis,
  url: System.get_env("REDIS_URL"),
  node_name: System.get_env("NODE_NAME", "node1")
```

---

## 7. Background Jobs

### 7.1 Oban Configuration

```elixir
# config/config.exs
config :conezia, Oban,
  repo: Conezia.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # 7 days
    {Oban.Plugins.Cron,
     crontab: [
       {"0 8 * * *", Conezia.Workers.DailyDigest},      # 8 AM daily
       {"0 * * * *", Conezia.Workers.ReminderCheck},    # Every hour
       {"*/5 * * * *", Conezia.Workers.HealthCheck},    # Every 5 min
       {"0 2 * * *", Conezia.Workers.CleanupExpired}    # 2 AM daily
     ]}
  ],
  queues: [
    default: 10,
    imports: 5,
    notifications: 20,
    webhooks: 10,
    mailers: 10
  ]
```

### 7.2 Job Workers

```elixir
# Import processing
defmodule Conezia.Workers.ProcessImport do
  use Oban.Worker, queue: :imports, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_job_id" => id}}) do
    Conezia.Imports.process_import(id)
  end
end

# Reminder notifications
defmodule Conezia.Workers.ReminderCheck do
  use Oban.Worker, queue: :notifications

  @impl Oban.Worker
  def perform(_job) do
    Conezia.Reminders.process_due_reminders()
  end
end

# Webhook delivery
defmodule Conezia.Workers.DeliverWebhook do
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_id" => id, "event" => event, "payload" => payload}}) do
    Conezia.Platform.deliver_webhook(id, event, payload)
  end
end
```

---

## 8. Caching Strategy

### 8.1 Cache Layers

```
┌─────────────────────────────────────────────────────────────┐
│                      Caching Strategy                        │
└─────────────────────────────────────────────────────────────┘

1. ETS (In-Process):
   - Rate limit counters (per-node)
   - Frequently accessed config

2. Redis:
   - User sessions
   - API rate limits (distributed)
   - Recently accessed entities (TTL: 5 min)
   - Search result cache (TTL: 1 min)
   - Webhook delivery deduplication

3. PostgreSQL:
   - Materialized views for dashboards
   - Denormalized counts (entity_count, etc.)
```

### 8.2 Cache Implementation

```elixir
defmodule Conezia.Cache do
  @moduledoc "Caching utilities using Redis"

  def get(key) do
    case Redix.command(:cache, ["GET", key]) do
      {:ok, nil} -> {:miss, nil}
      {:ok, value} -> {:hit, Jason.decode!(value)}
      {:error, _} -> {:miss, nil}
    end
  end

  def set(key, value, ttl_seconds \\ 300) do
    Redix.command(:cache, ["SETEX", key, ttl_seconds, Jason.encode!(value)])
  end

  def delete(key) do
    Redix.command(:cache, ["DEL", key])
  end

  def invalidate_pattern(pattern) do
    {:ok, keys} = Redix.command(:cache, ["KEYS", pattern])
    if keys != [], do: Redix.command(:cache, ["DEL" | keys])
  end
end
```

---

## 9. Error Handling

### 9.1 Error Types

```elixir
defmodule Conezia.Error do
  defexception [:type, :message, :details]

  @types %{
    not_found: {404, "Resource not found"},
    unauthorized: {401, "Authentication required"},
    forbidden: {403, "Access denied"},
    validation: {422, "Validation failed"},
    conflict: {409, "Resource conflict"},
    rate_limited: {429, "Rate limit exceeded"},
    internal: {500, "Internal server error"}
  }

  def not_found(resource, id) do
    %__MODULE__{
      type: :not_found,
      message: "#{resource} not found",
      details: %{resource: resource, id: id}
    }
  end

  def validation(changeset) do
    %__MODULE__{
      type: :validation,
      message: "Validation failed",
      details: %{errors: format_changeset_errors(changeset)}
    }
  end
end
```

### 9.2 Fallback Controller

```elixir
defmodule ConeziaWeb.FallbackController do
  use ConeziaWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ConeziaWeb.ErrorJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ConeziaWeb.ErrorJSON)
    |> render(:error, message: "Resource not found")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: ConeziaWeb.ErrorJSON)
    |> render(:error, message: "Authentication required")
  end
end
```

---

## 10. Monitoring & Observability

### 10.1 Telemetry Events

```elixir
# Custom telemetry events
:telemetry.execute(
  [:conezia, :entity, :created],
  %{count: 1},
  %{user_id: user.id, entity_type: entity.type}
)

:telemetry.execute(
  [:conezia, :import, :completed],
  %{duration: duration, records: count},
  %{user_id: user.id, source: source}
)
```

### 10.2 Metrics

```elixir
# lib/conezia/telemetry.ex
defmodule Conezia.Telemetry do
  def metrics do
    [
      # Phoenix metrics
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration", unit: {:native, :millisecond}),

      # Database metrics
      summary("conezia.repo.query.total_time", unit: {:native, :millisecond}),
      counter("conezia.repo.query.count"),

      # Business metrics
      counter("conezia.entity.created.count", tags: [:entity_type]),
      counter("conezia.communication.sent.count", tags: [:channel]),
      counter("conezia.reminder.completed.count"),
      counter("conezia.import.completed.count", tags: [:source]),

      # Oban metrics
      summary("oban.job.stop.duration", unit: {:native, :millisecond}),
      counter("oban.job.exception.count", tags: [:worker])
    ]
  end
end
```

---

## 11. Deployment Architecture

### 11.1 Production Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                     Production Deployment                        │
└─────────────────────────────────────────────────────────────────┘

                        ┌───────────────┐
                        │  CloudFlare   │
                        │     CDN       │
                        └───────┬───────┘
                                │
                        ┌───────▼───────┐
                        │  Application  │
                        │  Load Balancer│
                        └───────┬───────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
       ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
       │  Phoenix    │  │  Phoenix    │  │  Phoenix    │
       │  Container  │  │  Container  │  │  Container  │
       │  (2 CPU,    │  │  (2 CPU,    │  │  (2 CPU,    │
       │   4GB RAM)  │  │   4GB RAM)  │  │   4GB RAM)  │
       └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
              │                │                 │
              └────────────────┼─────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
┌───────────────┐    ┌─────────────────┐    ┌───────────────┐
│  PostgreSQL   │    │     Redis       │    │   S3/MinIO    │
│  Primary      │    │   Cluster       │    │   Storage     │
│  (4 CPU,      │◄──▶│  (2 CPU,        │    │               │
│   16GB RAM)   │    │   4GB RAM)      │    │               │
└───────┬───────┘    └─────────────────┘    └───────────────┘
        │
        ▼
┌───────────────┐
│  PostgreSQL   │
│  Read Replica │
└───────────────┘
```

### 11.2 Environment Configuration

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :conezia, Conezia.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    ssl: true

  config :conezia, ConeziaWeb.Endpoint,
    url: [host: System.fetch_env!("PHX_HOST"), port: 443, scheme: "https"],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

  config :conezia, :redis,
    url: System.fetch_env!("REDIS_URL")

  config :conezia, :s3,
    bucket: System.fetch_env!("S3_BUCKET"),
    region: System.get_env("AWS_REGION", "us-east-1")
end
```

---

## 12. Security Considerations

### 12.1 Security Measures

| Area | Measure |
|------|---------|
| **Transport** | TLS 1.3 only, HSTS enabled |
| **Authentication** | Argon2id for passwords, secure session tokens |
| **Authorization** | Policy-based access control, scope verification |
| **Input Validation** | Ecto changesets, parameterized queries |
| **Secrets** | Encrypted at rest (Vault/AWS Secrets Manager) |
| **Rate Limiting** | Per-IP and per-user limits |
| **CSRF** | Phoenix CSRF protection for forms |
| **XSS** | Content Security Policy, output encoding |
| **Sensitive Data** | Field-level encryption for SSN, credentials |

### 12.2 Rate Limiting Configuration

Rate limits are enforced per tier and scale with the user's subscription:

| Tier | API Requests/Hour | Entities Limit | Import Records/Month | Webhooks |
|------|-------------------|----------------|---------------------|----------|
| **Free** | 100 | 100 | 500 | 0 |
| **Personal** | 1,000 | 5,000 | 10,000 | 2 |
| **Professional** | 10,000 | Unlimited | 100,000 | 10 |
| **Enterprise** | 100,000 | Unlimited | Unlimited | 50 |

**Implementation:**

```elixir
defmodule Conezia.RateLimiter do
  @moduledoc "Rate limiting by tier"

  @tier_limits %{
    free: %{requests_per_hour: 100, entities: 100},
    personal: %{requests_per_hour: 1_000, entities: 5_000},
    professional: %{requests_per_hour: 10_000, entities: :unlimited},
    enterprise: %{requests_per_hour: 100_000, entities: :unlimited}
  }

  def check_rate_limit(user_id, tier) do
    key = "rate_limit:#{user_id}:#{current_hour()}"
    limit = @tier_limits[tier][:requests_per_hour]

    case Redix.command(:cache, ["INCR", key]) do
      {:ok, count} when count == 1 ->
        Redix.command(:cache, ["EXPIRE", key, 3600])
        {:ok, limit - count}
      {:ok, count} when count <= limit ->
        {:ok, limit - count}
      {:ok, count} ->
        {:error, :rate_limited, count - limit}
    end
  end

  def check_entity_limit(user_id, tier) do
    limit = @tier_limits[tier][:entities]
    if limit == :unlimited do
      :ok
    else
      count = Conezia.Entities.count_user_entities(user_id)
      if count < limit, do: :ok, else: {:error, :entity_limit_reached}
    end
  end

  defp current_hour do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> then(&(&1.hour))
  end
end
```

**Plug Middleware:**

```elixir
defmodule ConeziaWeb.Plugs.RateLimiter do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user do
      case Conezia.RateLimiter.check_rate_limit(user.id, user.tier) do
        {:ok, remaining} ->
          conn
          |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
          |> put_resp_header("x-ratelimit-limit", to_string(get_limit(user.tier)))

        {:error, :rate_limited, retry_after} ->
          conn
          |> put_status(429)
          |> put_resp_header("retry-after", to_string(retry_after))
          |> Phoenix.Controller.json(%{error: "Rate limit exceeded"})
          |> halt()
      end
    else
      conn
    end
  end

  defp get_limit(tier), do: Conezia.RateLimiter.tier_limits()[tier][:requests_per_hour]
end
```

### 12.3 Sensitive Field Encryption

**Encrypted Fields:**
- `identifiers.value` (when type is `ssn`, `government_id`, `account_number`)
- `external_accounts.credentials` (OAuth tokens)
- `external_accounts.refresh_token`

**Implementation:**

```elixir
defmodule Conezia.Encrypted.Binary do
  @behaviour Ecto.Type

  def type, do: :binary

  def cast(value), do: {:ok, value}

  def dump(value) do
    {:ok, Conezia.Vault.encrypt(value)}
  end

  def load(value) do
    {:ok, Conezia.Vault.decrypt(value)}
  end
end
```

### 12.4 Encryption Key Management

**Key Derivation:**

```elixir
defmodule Conezia.Vault do
  @moduledoc "Field-level encryption using AES-256-GCM"

  @aad "Conezia"  # Additional Authenticated Data

  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_current_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key,
        iv,
        plaintext,
        @aad,
        true
      )

    # Format: version (1 byte) + key_id (4 bytes) + iv (12 bytes) + tag (16 bytes) + ciphertext
    <<1::8, current_key_id()::32, iv::binary, tag::binary, ciphertext::binary>>
  end

  def decrypt(<<1::8, key_id::32, iv::12-binary, tag::16-binary, ciphertext::binary>>) do
    key = get_key_by_id(key_id)

    :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      key,
      iv,
      ciphertext,
      @aad,
      tag,
      false
    )
  end

  defp get_current_key do
    # In production, fetch from AWS KMS, HashiCorp Vault, or env var
    System.fetch_env!("ENCRYPTION_KEY") |> Base.decode64!()
  end

  defp get_key_by_id(key_id) do
    # Support key rotation by looking up historical keys
    Conezia.KeyStore.get_key(key_id)
  end

  defp current_key_id, do: 1
end
```

**Key Rotation Strategy:**

1. **Generation**: Keys are generated using `mix phx.gen.secret 32 | base64`
2. **Storage**: Keys stored in AWS KMS or HashiCorp Vault (never in code/config files)
3. **Rotation Schedule**: Every 90 days for compliance
4. **Rotation Process**:
   - New key added to KeyStore with new key_id
   - New data encrypted with new key
   - Background job re-encrypts existing data with new key
   - Old key retained for 30 days after rotation completes
   - Old key deleted after grace period

**Environment Variables:**

```bash
# Primary encryption key (base64-encoded 32 bytes)
ENCRYPTION_KEY=<base64-encoded-32-byte-key>

# For AWS KMS integration (recommended for production)
AWS_KMS_KEY_ID=alias/conezia-encryption-key
```

---

## 13. Smart Group Execution

### 13.1 Smart Group Membership Strategy

Smart groups can have two execution strategies:

| Strategy | Description | Use Case |
|----------|-------------|----------|
| **Lazy (Default)** | Computed on-read | Small datasets, real-time accuracy |
| **Cached** | Background computed, cached | Large datasets, performance |

**Implementation:**

```elixir
defmodule Conezia.Entities.SmartGroup do
  @moduledoc "Smart group membership computation"

  @cache_ttl 300  # 5 minutes

  def get_members(group, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :lazy)

    case strategy do
      :lazy -> compute_members(group)
      :cached -> get_cached_or_compute(group)
    end
  end

  defp compute_members(%{rules: rules, user_id: user_id}) do
    base_query()
    |> apply_rules(rules)
    |> where([e], e.owner_id == ^user_id)
    |> Repo.all()
  end

  defp apply_rules(query, rules) do
    Enum.reduce(rules, query, fn
      {"type", type}, q -> where(q, [e], e.type == ^type)
      {"tags", tags}, q -> join_and_filter_tags(q, tags)
      {"relationship_status", status}, q -> join_and_filter_relationship(q, :status, status)
      {"last_interaction_days", days}, q ->
        cutoff = DateTime.add(DateTime.utc_now(), -days * 86400, :second)
        where(q, [e], e.last_interaction_at < ^cutoff or is_nil(e.last_interaction_at))
      _, q -> q
    end)
  end

  defp get_cached_or_compute(group) do
    cache_key = "smart_group:#{group.id}:members"

    case Conezia.Cache.get(cache_key) do
      {:hit, members} -> members
      {:miss, _} ->
        members = compute_members(group)
        Conezia.Cache.set(cache_key, Enum.map(members, & &1.id), @cache_ttl)
        members
    end
  end
end
```

**Cache Invalidation Triggers:**

Smart group caches are invalidated when:
- An entity is created, updated, or deleted
- A tag is added or removed from an entity
- A relationship status changes
- An interaction occurs (updates `last_interaction_at`)

```elixir
# In entity context
def create_entity(attrs) do
  with {:ok, entity} <- do_create_entity(attrs) do
    invalidate_smart_groups(entity.owner_id)
    {:ok, entity}
  end
end

defp invalidate_smart_groups(user_id) do
  Conezia.Cache.invalidate_pattern("smart_group:*:#{user_id}:*")
end
```

---

*Document Version: 1.1*
*Created: 2026-01-17*
