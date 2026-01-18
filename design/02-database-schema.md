# Conezia Database Schema Design

## 1. Overview

This document defines the PostgreSQL database schema for Conezia, including tables, indexes, constraints, and migrations.

### 1.1 Database Configuration

```elixir
# config/config.exs
config :conezia, Conezia.Repo,
  adapter: Ecto.Adapters.Postgres,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]
```

### 1.2 Conventions

- **Primary Keys**: UUID (binary_id) for all tables
- **Timestamps**: `inserted_at`, `updated_at` using UTC datetime with microseconds
- **Soft Deletes**: `archived_at` or `deleted_at` where applicable
- **Foreign Keys**: Always indexed, with appropriate ON DELETE actions
- **Naming**: snake_case for tables and columns

### 1.3 Migration Order

Migrations must be run in this order due to foreign key dependencies:

| Order | Migration | Dependencies |
|-------|-----------|--------------|
| 1 | `EnableExtensions` | None |
| 2 | `CreateUsers` | None |
| 3 | `CreateAuthProviders` | users |
| 4 | `CreateUserTokens` | users |
| 5 | `CreateEntities` | users |
| 6 | `CreateRelationships` | users, entities |
| 7 | `CreateIdentifiers` | entities |
| 8 | `CreateTags` | users |
| 9 | `CreateEntityTags` | entities, tags |
| 10 | `CreateGroups` | users |
| 11 | `CreateEntityGroups` | entities, groups |
| 12 | `CreateConversations` | users, entities |
| 13 | `CreateCommunications` | users, entities, conversations |
| 14 | `CreateInteractions` | users, entities |
| 15 | `CreateReminders` | users, entities |
| 16 | `CreateExternalAccounts` | users, entities |
| 17 | `CreateAttachments` | users, entities, interactions, communications |
| 18 | `CreateActivityLogs` | users |
| 19 | `CreateImportJobs` | users |
| 20 | `CreateApplications` | users |
| 21 | `CreateApplicationUsers` | applications, users |
| 22 | `CreateWebhooks` | applications |
| 23 | `CreateWebhookDeliveries` | webhooks |
| 24 | `SetupFullTextSearch` | entities, identifiers, interactions, communications |

**Note:** When generating migrations, use `mix ecto.gen.migration` with timestamps that preserve this order (e.g., `20260117000001_enable_extensions`, `20260117000002_create_users`, etc.).

---

## 2. Core Schemas

### 2.1 Users

```elixir
defmodule Conezia.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @tiers ~w(free personal professional enterprise)

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :timezone, :string, default: "UTC"
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :tier, :string, default: "free"  # Subscription tier for rate limiting
    field :settings, :map, default: %{}
    field :onboarding_completed_at, :utc_datetime_usec  # Track onboarding completion
    field :notification_preferences, :map, default: %{
      "email" => true,
      "push" => true,
      "in_app" => true,
      "quiet_hours_start" => nil,  # e.g., "22:00"
      "quiet_hours_end" => nil     # e.g., "08:00"
    }

    has_many :auth_providers, Conezia.Accounts.AuthProvider
    has_many :entities, Conezia.Entities.Entity, foreign_key: :owner_id
    has_many :tags, Conezia.Entities.Tag
    has_many :groups, Conezia.Entities.Group
    has_many :reminders, Conezia.Reminders.Reminder
    has_many :external_accounts, Conezia.ExternalAccounts.ExternalAccount

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:email]
  @optional_fields [:name, :avatar_url, :timezone, :settings, :tier,
                    :onboarding_completed_at, :notification_preferences]

  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_email()
    |> validate_timezone()
    |> validate_inclusion(:tier, @tiers)
  end

  def preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:settings, :notification_preferences])
    |> validate_notification_preferences()
  end

  defp validate_notification_preferences(changeset) do
    validate_change(changeset, :notification_preferences, fn :notification_preferences, prefs ->
      cond do
        not is_map(prefs) -> [notification_preferences: "must be a map"]
        prefs["quiet_hours_start"] && !valid_time?(prefs["quiet_hours_start"]) ->
          [notification_preferences: "quiet_hours_start must be HH:MM format"]
        prefs["quiet_hours_end"] && !valid_time?(prefs["quiet_hours_end"]) ->
          [notification_preferences: "quiet_hours_end must be HH:MM format"]
        true -> []
      end
    end)
  end

  defp valid_time?(time) when is_binary(time) do
    Regex.match?(~r/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/, time)
  end
  defp valid_time?(_), do: false

  def valid_tiers, do: @tiers

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_password()
    |> hash_password()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 254)
    |> unsafe_validate_unique(:email, Conezia.Repo)
    |> unique_constraint(:email)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_timezone(changeset) do
    validate_change(changeset, :timezone, fn :timezone, tz ->
      if tz in Tzdata.zone_list() do
        []
      else
        [timezone: "must be a valid IANA timezone"]
      end
    end)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> validate_format(:password, ~r/[a-z]/, message: "must contain a lowercase letter")
    |> validate_format(:password, ~r/[A-Z]/, message: "must contain an uppercase letter")
    |> validate_format(:password, ~r/[0-9]/, message: "must contain a number")
  end

  defp hash_password(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :hashed_password, Argon2.hash_pwd_salt(password))
      _ ->
        changeset
    end
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :name, :string, size: 255
      add :avatar_url, :string, size: 2048
      add :timezone, :string, size: 64, default: "UTC"
      add :hashed_password, :string, size: 255
      add :confirmed_at, :utc_datetime_usec
      add :tier, :string, size: 16, default: "free"
      add :settings, :map, default: %{}
      add :onboarding_completed_at, :utc_datetime_usec
      add :notification_preferences, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create index(:users, [:inserted_at])
    create index(:users, [:tier])
  end
end
```

### 2.2 Auth Providers

```elixir
defmodule Conezia.Accounts.AuthProvider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(google apple facebook linkedin)

  schema "auth_providers" do
    field :provider, :string
    field :provider_uid, :string
    field :provider_token, Conezia.Encrypted.Binary
    field :provider_refresh_token, Conezia.Encrypted.Binary
    field :provider_meta, :map, default: %{}

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(auth_provider, attrs) do
    auth_provider
    |> cast(attrs, [:provider, :provider_uid, :provider_token, :provider_refresh_token, :provider_meta, :user_id])
    |> validate_required([:provider, :provider_uid, :user_id])
    |> validate_inclusion(:provider, @providers)
    |> unique_constraint([:provider, :provider_uid])
    |> foreign_key_constraint(:user_id)
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateAuthProviders do
  use Ecto.Migration

  def change do
    create table(:auth_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, size: 32, null: false
      add :provider_uid, :string, size: 255, null: false
      add :provider_token, :binary
      add :provider_refresh_token, :binary
      add :provider_meta, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:auth_providers, [:provider, :provider_uid])
    create index(:auth_providers, [:user_id])
  end
end
```

### 2.3 User Sessions

```elixir
defmodule Conezia.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @hash_algorithm :sha256
  @rand_size 32

  # Token validity periods
  @session_validity_days 60
  @reset_password_validity_hours 1
  @confirm_email_validity_hours 24

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  def verify_session_token_query(token) do
    query =
      from t in __MODULE__,
        where: t.token == ^token and t.context == "session",
        where: t.inserted_at > ago(@session_validity_days, "day"),
        join: u in assoc(t, :user),
        select: u

    {:ok, query}
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateUserTokens do
  use Ecto.Migration

  def change do
    create table(:user_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, size: 32, null: false
      add :sent_to, :string, size: 254

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:user_tokens, [:user_id])
    create unique_index(:user_tokens, [:context, :token])
  end
end
```

---

## 3. Entity Schemas

### 3.1 Entities

```elixir
defmodule Conezia.Entities.Entity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entity_types ~w(person organization service thing animal abstract)

  schema "entities" do
    field :type, :string
    field :name, :string
    field :description, :string
    field :avatar_url, :string
    field :metadata, :map, default: %{}
    field :last_interaction_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec

    belongs_to :owner, Conezia.Accounts.User
    has_many :relationships, Conezia.Entities.Relationship  # A user's relationship to this entity
    has_many :identifiers, Conezia.Entities.Identifier
    has_many :interactions, Conezia.Interactions.Interaction
    has_many :conversations, Conezia.Communications.Conversation
    has_many :reminders, Conezia.Reminders.Reminder
    has_many :attachments, Conezia.Attachments.Attachment

    many_to_many :tags, Conezia.Entities.Tag, join_through: "entity_tags"
    many_to_many :groups, Conezia.Entities.Group, join_through: "entity_groups"

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :name, :owner_id]
  @optional_fields [:description, :avatar_url, :metadata, :last_interaction_at, :archived_at]

  def changeset(entity, attrs) do
    entity
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @entity_types)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 10_000)
    |> validate_url(:avatar_url)
    |> foreign_key_constraint(:owner_id)
  end

  def archive_changeset(entity) do
    change(entity, archived_at: DateTime.utc_now())
  end

  def touch_interaction_changeset(entity) do
    change(entity, last_interaction_at: DateTime.utc_now())
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
          []
        _ ->
          [{field, "must be a valid URL"}]
      end
    end)
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateEntities do
  use Ecto.Migration

  def change do
    create table(:entities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32, null: false
      add :name, :string, size: 255, null: false
      add :description, :text
      add :avatar_url, :string, size: 2048
      add :metadata, :map, default: %{}
      add :last_interaction_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:entities, [:owner_id])
    create index(:entities, [:owner_id, :type])
    create index(:entities, [:owner_id, :archived_at])
    create index(:entities, [:last_interaction_at])

    # Full-text search index
    execute """
    CREATE INDEX entities_name_trgm_idx ON entities USING gin (name gin_trgm_ops);
    """, """
    DROP INDEX entities_name_trgm_idx;
    """
  end
end
```

### 3.2 Relationships

```elixir
defmodule Conezia.Entities.Relationship do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @relationship_types ~w(friend family colleague client vendor acquaintance service_provider other)
  @strength_levels ~w(close regular acquaintance)
  @statuses ~w(active inactive archived)

  schema "relationships" do
    field :type, :string
    field :strength, :string, default: "regular"
    field :status, :string, default: "active"
    field :started_at, :date
    field :health_threshold_days, :integer, default: 30
    field :notes, :string

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :entity_id]
  @optional_fields [:type, :strength, :status, :started_at, :health_threshold_days, :notes]

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @relationship_types)
    |> validate_inclusion(:strength, @strength_levels)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:health_threshold_days, greater_than: 0, less_than_or_equal_to: 365)
    |> validate_length(:notes, max: 5000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
    |> unique_constraint([:user_id, :entity_id])
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def change do
    create table(:relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32
      add :strength, :string, size: 16, default: "regular"
      add :status, :string, size: 16, default: "active"
      add :started_at, :date
      add :health_threshold_days, :integer, default: 30
      add :notes, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:relationships, [:user_id, :entity_id])
    create index(:relationships, [:user_id, :status])
    create index(:relationships, [:entity_id])
  end
end
```

### 3.3 Identifiers

```elixir
defmodule Conezia.Entities.Identifier do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @identifier_types ~w(phone email ssn government_id account_number social_handle website)
  @sensitive_types ~w(ssn government_id account_number)

  schema "identifiers" do
    field :type, :string
    field :value, :string
    field :value_encrypted, Conezia.Encrypted.Binary
    field :value_hash, :string  # For duplicate detection of encrypted values
    field :label, :string
    field :is_primary, :boolean, default: false
    field :verified_at, :utc_datetime_usec

    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :entity_id]
  @optional_fields [:value, :label, :is_primary, :verified_at]

  def changeset(identifier, attrs) do
    identifier
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @identifier_types)
    |> validate_length(:label, max: 64)
    |> validate_identifier_value()
    |> encrypt_sensitive_value()
    |> hash_value_for_duplicate_detection()
    |> foreign_key_constraint(:entity_id)
  end

  defp validate_identifier_value(changeset) do
    type = get_field(changeset, :type)
    value = get_change(changeset, :value)

    if value do
      case type do
        "phone" -> validate_phone(changeset, value)
        "email" -> validate_email(changeset, value)
        "ssn" -> validate_ssn(changeset, value)
        "website" -> validate_url(changeset, value)
        _ -> changeset
      end
    else
      add_error(changeset, :value, "is required")
    end
  end

  defp validate_phone(changeset, value) do
    # E.164 format validation
    if Regex.match?(~r/^\+[1-9]\d{1,14}$/, value) do
      changeset
    else
      add_error(changeset, :value, "must be in E.164 format (e.g., +12025551234)")
    end
  end

  defp validate_email(changeset, value) do
    if Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, value) do
      changeset
      |> update_change(:value, &String.downcase/1)
    else
      add_error(changeset, :value, "must be a valid email address")
    end
  end

  defp validate_ssn(changeset, value) do
    # US SSN format: XXX-XX-XXXX
    if Regex.match?(~r/^\d{3}-\d{2}-\d{4}$/, value) do
      changeset
    else
      add_error(changeset, :value, "must be in format XXX-XX-XXXX")
    end
  end

  defp validate_url(changeset, value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        changeset
      _ ->
        add_error(changeset, :value, "must be a valid URL")
    end
  end

  defp encrypt_sensitive_value(changeset) do
    type = get_field(changeset, :type)
    value = get_change(changeset, :value)

    if type in @sensitive_types and value do
      changeset
      |> put_change(:value_encrypted, value)
      |> put_change(:value, nil)  # Don't store plaintext
    else
      changeset
    end
  end

  defp hash_value_for_duplicate_detection(changeset) do
    value = get_change(changeset, :value) || get_change(changeset, :value_encrypted)

    if value do
      hash = :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
      put_change(changeset, :value_hash, hash)
    else
      changeset
    end
  end

  def sensitive_type?(type), do: type in @sensitive_types
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateIdentifiers do
  use Ecto.Migration

  def change do
    create table(:identifiers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32, null: false
      add :value, :string, size: 512  # Plaintext for non-sensitive
      add :value_encrypted, :binary    # Encrypted for sensitive
      add :value_hash, :string, size: 64  # For duplicate detection
      add :label, :string, size: 64
      add :is_primary, :boolean, default: false
      add :verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:identifiers, [:entity_id])
    create index(:identifiers, [:type, :value_hash])  # For duplicate detection
    create index(:identifiers, [:entity_id, :is_primary])

    # Partial unique index for primary identifiers per type per entity
    execute """
    CREATE UNIQUE INDEX identifiers_entity_type_primary_idx
    ON identifiers (entity_id, type)
    WHERE is_primary = true;
    """, """
    DROP INDEX identifiers_entity_type_primary_idx;
    """
  end
end
```

### 3.4 Tags

```elixir
defmodule Conezia.Entities.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @colors ~w(red orange yellow green blue purple pink gray)

  schema "tags" do
    field :name, :string
    field :color, :string, default: "blue"
    field :description, :string

    belongs_to :user, Conezia.Accounts.User
    many_to_many :entities, Conezia.Entities.Entity, join_through: "entity_tags"

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :user_id]
  @optional_fields [:color, :description]

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 50)
    |> validate_inclusion(:color, @colors)
    |> validate_length(:description, max: 255)
    |> unique_constraint([:user_id, :name])
    |> foreign_key_constraint(:user_id)
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 50, null: false
      add :color, :string, size: 16, default: "blue"
      add :description, :string, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tags, [:user_id, :name])
    create index(:tags, [:user_id])

    # Join table for entity-tag relationship
    create table(:entity_tags, primary_key: false) do
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:entity_tags, [:entity_id, :tag_id])
    create index(:entity_tags, [:tag_id])
  end
end
```

### 3.5 Groups

```elixir
defmodule Conezia.Entities.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "groups" do
    field :name, :string
    field :description, :string
    field :is_smart, :boolean, default: false
    field :rules, :map  # Smart group filter rules

    belongs_to :user, Conezia.Accounts.User
    many_to_many :entities, Conezia.Entities.Entity, join_through: "entity_groups"

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :user_id]
  @optional_fields [:description, :is_smart, :rules]

  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_smart_group_rules()
    |> unique_constraint([:user_id, :name])
    |> foreign_key_constraint(:user_id)
  end

  defp validate_smart_group_rules(changeset) do
    is_smart = get_field(changeset, :is_smart)
    rules = get_field(changeset, :rules)

    cond do
      is_smart and (is_nil(rules) or rules == %{}) ->
        add_error(changeset, :rules, "is required for smart groups")
      is_smart ->
        validate_rules_schema(changeset, rules)
      true ->
        changeset
    end
  end

  defp validate_rules_schema(changeset, rules) do
    # Validate smart group rule structure
    valid_fields = ~w(type tags relationship_type relationship_status last_interaction_days)

    case rules do
      %{} = r when map_size(r) > 0 ->
        invalid_keys = Map.keys(r) -- valid_fields
        if invalid_keys == [] do
          changeset
        else
          add_error(changeset, :rules, "contains invalid fields: #{inspect(invalid_keys)}")
        end
      _ ->
        add_error(changeset, :rules, "must be a valid rules object")
    end
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 100, null: false
      add :description, :string, size: 500
      add :is_smart, :boolean, default: false
      add :rules, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:groups, [:user_id, :name])
    create index(:groups, [:user_id])

    # Join table for entity-group relationship
    create table(:entity_groups, primary_key: false) do
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :added_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:entity_groups, [:entity_id, :group_id])
    create index(:entity_groups, [:group_id])
  end
end
```

---

## 4. Communication Schemas

### 4.1 Conversations

```elixir
defmodule Conezia.Communications.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channels ~w(internal email sms whatsapp telegram phone)

  schema "conversations" do
    field :channel, :string
    field :subject, :string
    field :last_message_at, :utc_datetime_usec
    field :is_archived, :boolean, default: false

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity
    has_many :communications, Conezia.Communications.Communication

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:channel, :user_id, :entity_id]
  @optional_fields [:subject, :last_message_at, :is_archived]

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:channel, @channels)
    |> validate_length(:subject, max: 255)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end
end
```

### 4.2 Communications (Messages)

```elixir
defmodule Conezia.Communications.Communication do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channels ~w(internal email sms whatsapp telegram phone)
  @directions ~w(inbound outbound)

  schema "communications" do
    field :channel, :string
    field :direction, :string
    field :content, :string
    field :attachments, {:array, :map}, default: []
    field :sent_at, :utc_datetime_usec
    field :read_at, :utc_datetime_usec
    field :external_id, :string  # ID from external system (email ID, etc.)

    belongs_to :conversation, Conezia.Communications.Conversation
    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:channel, :direction, :content, :user_id, :entity_id]
  @optional_fields [:conversation_id, :attachments, :sent_at, :read_at, :external_id]

  def changeset(communication, attrs) do
    communication
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:direction, @directions)
    |> validate_length(:content, min: 1, max: 100_000)
    |> validate_attachments()
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  defp validate_attachments(changeset) do
    validate_change(changeset, :attachments, fn :attachments, attachments ->
      Enum.flat_map(attachments, fn attachment ->
        case attachment do
          %{"id" => _, "filename" => _, "mime_type" => _} -> []
          _ -> [attachments: "each attachment must have id, filename, and mime_type"]
        end
      end)
    end)
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateCommunications do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :string, size: 32, null: false
      add :subject, :string, size: 255
      add :last_message_at, :utc_datetime_usec
      add :is_archived, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversations, [:user_id, :is_archived])
    create index(:conversations, [:entity_id])
    create index(:conversations, [:last_message_at])

    create table(:communications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :string, size: 32, null: false
      add :direction, :string, size: 16, null: false
      add :content, :text, null: false
      add :attachments, {:array, :map}, default: []
      add :sent_at, :utc_datetime_usec
      add :read_at, :utc_datetime_usec
      add :external_id, :string, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create index(:communications, [:conversation_id])
    create index(:communications, [:user_id, :entity_id])
    create index(:communications, [:sent_at])
    create index(:communications, [:external_id])
  end
end
```

---

## 5. Interaction & Reminder Schemas

### 5.1 Interactions

```elixir
defmodule Conezia.Interactions.Interaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @interaction_types ~w(note meeting call transaction event document other)

  schema "interactions" do
    field :type, :string
    field :title, :string
    field :content, :string
    field :occurred_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity
    has_many :attachments, Conezia.Attachments.Attachment

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :content, :user_id, :entity_id]
  @optional_fields [:title, :occurred_at]

  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @interaction_types)
    |> validate_length(:title, max: 255)
    |> validate_length(:content, min: 1, max: 50_000)
    |> set_default_occurred_at()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  defp set_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
```

### 5.2 Reminders

```elixir
defmodule Conezia.Reminders.Reminder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reminder_types ~w(follow_up birthday anniversary custom health_alert event)
  @notification_channels ~w(in_app email push)

  schema "reminders" do
    field :type, :string
    field :title, :string
    field :description, :string
    field :due_at, :utc_datetime_usec
    field :recurrence_rule, :map  # RFC 5545 RRULE as JSON
    field :notification_channels, {:array, :string}, default: ["in_app"]
    field :snoozed_until, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity  # Optional

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :title, :due_at, :user_id]
  @optional_fields [:description, :recurrence_rule, :notification_channels, :snoozed_until, :completed_at, :entity_id]

  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @reminder_types)
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> validate_notification_channels()
    |> validate_recurrence_rule()
    |> validate_due_at_in_future()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  def snooze_changeset(reminder, until) do
    change(reminder, snoozed_until: until)
    |> validate_snooze_time()
  end

  def complete_changeset(reminder) do
    change(reminder, completed_at: DateTime.utc_now())
  end

  defp validate_notification_channels(changeset) do
    validate_change(changeset, :notification_channels, fn :notification_channels, channels ->
      invalid = channels -- @notification_channels
      if invalid == [] do
        []
      else
        [notification_channels: "contains invalid channels: #{inspect(invalid)}"]
      end
    end)
  end

  defp validate_recurrence_rule(changeset) do
    validate_change(changeset, :recurrence_rule, fn :recurrence_rule, rule ->
      case rule do
        nil -> []
        %{"freq" => freq} when freq in ~w(daily weekly monthly yearly) -> []
        _ -> [recurrence_rule: "must have a valid freq (daily, weekly, monthly, yearly)"]
      end
    end)
  end

  defp validate_due_at_in_future(changeset) do
    if changeset.valid? and get_change(changeset, :due_at) do
      due_at = get_change(changeset, :due_at)
      if DateTime.compare(due_at, DateTime.utc_now()) == :gt do
        changeset
      else
        add_error(changeset, :due_at, "must be in the future")
      end
    else
      changeset
    end
  end

  defp validate_snooze_time(changeset) do
    until = get_change(changeset, :snoozed_until)
    if until && DateTime.compare(until, DateTime.utc_now()) == :gt do
      changeset
    else
      add_error(changeset, :snoozed_until, "must be in the future")
    end
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateInteractionsAndReminders do
  use Ecto.Migration

  def change do
    create table(:interactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, size: 32, null: false
      add :title, :string, size: 255
      add :content, :text, null: false
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:interactions, [:user_id])
    create index(:interactions, [:entity_id])
    create index(:interactions, [:occurred_at])

    create table(:reminders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :set_null)
      add :type, :string, size: 32, null: false
      add :title, :string, size: 255, null: false
      add :description, :text
      add :due_at, :utc_datetime_usec, null: false
      add :recurrence_rule, :map
      add :notification_channels, {:array, :string}, default: ["in_app"]
      add :snoozed_until, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reminders, [:user_id, :completed_at])
    create index(:reminders, [:user_id, :due_at])
    create index(:reminders, [:entity_id])

    # Index for finding due reminders
    execute """
    CREATE INDEX reminders_due_pending_idx ON reminders (due_at)
    WHERE completed_at IS NULL AND (snoozed_until IS NULL OR snoozed_until < now());
    """, """
    DROP INDEX reminders_due_pending_idx;
    """
  end
end
```

---

## 6. Attachment & Activity Log Schemas

### 6.1 Attachments

```elixir
defmodule Conezia.Attachments.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_file_size 50 * 1024 * 1024  # 50 MB
  @allowed_mime_types ~w(
    image/jpeg image/png image/gif image/webp
    application/pdf
    text/plain text/csv
    application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  )

  schema "attachments" do
    field :filename, :string
    field :mime_type, :string
    field :size_bytes, :integer
    field :storage_key, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity
    belongs_to :interaction, Conezia.Interactions.Interaction
    belongs_to :communication, Conezia.Communications.Communication

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:filename, :mime_type, :size_bytes, :storage_key, :user_id]
  @optional_fields [:entity_id, :interaction_id, :communication_id, :deleted_at]

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_inclusion(:mime_type, @allowed_mime_types)
    |> validate_number(:size_bytes, greater_than: 0, less_than_or_equal_to: @max_file_size)
    |> validate_at_least_one_parent()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
    |> foreign_key_constraint(:interaction_id)
    |> foreign_key_constraint(:communication_id)
  end

  defp validate_at_least_one_parent(changeset) do
    entity_id = get_field(changeset, :entity_id)
    interaction_id = get_field(changeset, :interaction_id)
    communication_id = get_field(changeset, :communication_id)

    if entity_id || interaction_id || communication_id do
      changeset
    else
      add_error(changeset, :entity_id, "at least one of entity_id, interaction_id, or communication_id is required")
    end
  end

  def max_file_size, do: @max_file_size
  def allowed_mime_types, do: @allowed_mime_types
end
```

### 6.2 Activity Log

```elixir
defmodule Conezia.Interactions.ActivityLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(create update delete view export login logout import)
  @resource_types ~w(entity relationship communication interaction reminder tag group attachment user)

  schema "activity_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :user_agent, :string

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:action, :resource_type, :user_id]
  @optional_fields [:resource_id, :metadata, :ip_address, :user_agent]

  def changeset(activity_log, attrs) do
    activity_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:resource_type, @resource_types)
    |> foreign_key_constraint(:user_id)
  end

  def log(user, action, resource_type, resource_id \\ nil, metadata \\ %{}, conn \\ nil) do
    attrs = %{
      user_id: user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata,
      ip_address: conn && get_ip(conn),
      user_agent: conn && get_user_agent(conn)
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> Conezia.Repo.insert()
  end

  defp get_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> String.slice(ua, 0, 512)
      _ -> nil
    end
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateAttachmentsAndActivityLogs do
  use Ecto.Migration

  def change do
    create table(:attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :set_null)
      add :interaction_id, references(:interactions, type: :binary_id, on_delete: :set_null)
      add :communication_id, references(:communications, type: :binary_id, on_delete: :set_null)
      add :filename, :string, size: 255, null: false
      add :mime_type, :string, size: 128, null: false
      add :size_bytes, :bigint, null: false
      add :storage_key, :string, size: 512, null: false
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:attachments, [:user_id])
    create index(:attachments, [:entity_id])
    create index(:attachments, [:interaction_id])
    create index(:attachments, [:communication_id])

    create table(:activity_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :action, :string, size: 32, null: false
      add :resource_type, :string, size: 32, null: false
      add :resource_id, :binary_id
      add :metadata, :map, default: %{}
      add :ip_address, :string, size: 45
      add :user_agent, :string, size: 512

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:activity_logs, [:user_id, :inserted_at])
    create index(:activity_logs, [:resource_type, :resource_id])

    # Partition activity_logs by month for performance (optional, for high volume)
    # This is a placeholder - actual partitioning requires more setup
  end
end
```

---

## 7. External Account Schema

### 7.1 External Accounts

```elixir
defmodule Conezia.ExternalAccounts.ExternalAccount do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @services ~w(google_contacts google_calendar icloud outlook linkedin)
  @statuses ~w(connected disconnected error pending_reauth)

  schema "external_accounts" do
    field :service_name, :string
    field :account_identifier, :string  # e.g., email address for the account
    field :credentials, Conezia.Encrypted.Binary  # OAuth tokens, encrypted
    field :refresh_token, Conezia.Encrypted.Binary
    field :status, :string, default: "connected"
    field :scopes, {:array, :string}, default: []
    field :last_synced_at, :utc_datetime_usec
    field :sync_error, :string
    field :metadata, :map, default: %{}

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity  # Optional: link to entity representing this service

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:service_name, :account_identifier, :user_id]
  @optional_fields [:credentials, :refresh_token, :status, :scopes, :last_synced_at,
                    :sync_error, :metadata, :entity_id]

  def changeset(external_account, attrs) do
    external_account
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:service_name, @services)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:account_identifier, max: 255)
    |> unique_constraint([:user_id, :service_name, :account_identifier])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
  end

  def mark_error_changeset(external_account, error_message) do
    change(external_account,
      status: "error",
      sync_error: error_message
    )
  end

  def mark_synced_changeset(external_account) do
    change(external_account,
      status: "connected",
      last_synced_at: DateTime.utc_now(),
      sync_error: nil
    )
  end

  def valid_services, do: @services
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateExternalAccounts do
  use Ecto.Migration

  def change do
    create table(:external_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :set_null)
      add :service_name, :string, size: 32, null: false
      add :account_identifier, :string, size: 255, null: false
      add :credentials, :binary  # Encrypted OAuth access token
      add :refresh_token, :binary  # Encrypted OAuth refresh token
      add :status, :string, size: 16, default: "connected"
      add :scopes, {:array, :string}, default: []
      add :last_synced_at, :utc_datetime_usec
      add :sync_error, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:external_accounts, [:user_id, :service_name, :account_identifier])
    create index(:external_accounts, [:user_id, :status])
    create index(:external_accounts, [:service_name])
  end
end
```

---

## 8. Import & Platform Schemas

### 8.1 Import Jobs

```elixir
defmodule Conezia.Imports.ImportJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources ~w(google csv vcard linkedin icloud outlook)
  @statuses ~w(pending processing completed failed cancelled)

  schema "import_jobs" do
    field :source, :string
    field :status, :string, default: "pending"
    field :total_records, :integer, default: 0
    field :processed_records, :integer, default: 0
    field :created_records, :integer, default: 0
    field :merged_records, :integer, default: 0
    field :skipped_records, :integer, default: 0
    field :error_log, {:array, :map}, default: []
    field :file_path, :string  # For file uploads
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:source, :user_id]
  @optional_fields [:status, :total_records, :processed_records, :created_records,
                    :merged_records, :skipped_records, :error_log, :file_path,
                    :started_at, :completed_at]

  def changeset(import_job, attrs) do
    import_job
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:total_records, greater_than_or_equal_to: 0)
    |> validate_number(:processed_records, greater_than_or_equal_to: 0)
    |> validate_number(:created_records, greater_than_or_equal_to: 0)
    |> validate_number(:merged_records, greater_than_or_equal_to: 0)
    |> validate_number(:skipped_records, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end

  def start_changeset(import_job) do
    change(import_job, status: "processing", started_at: DateTime.utc_now())
  end

  def complete_changeset(import_job, stats) do
    import_job
    |> change(stats)
    |> put_change(:status, "completed")
    |> put_change(:completed_at, DateTime.utc_now())
  end

  def fail_changeset(import_job, errors) do
    change(import_job,
      status: "failed",
      error_log: errors,
      completed_at: DateTime.utc_now()
    )
  end
end
```

### 8.2 Platform Application

```elixir
defmodule Conezia.Platform.Application do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved suspended)
  @scopes ~w(read:entities write:entities delete:entities read:communications
             write:communications read:reminders write:reminders read:profile write:profile)

  schema "applications" do
    field :name, :string
    field :description, :string
    field :logo_url, :string
    field :website_url, :string
    field :callback_urls, {:array, :string}, default: []
    field :api_key, :string
    field :api_key_hash, :string
    field :api_secret_hash, :string
    field :scopes, {:array, :string}, default: []
    field :status, :string, default: "pending"

    belongs_to :developer, Conezia.Accounts.User
    has_many :application_users, Conezia.Platform.ApplicationUser
    has_many :webhooks, Conezia.Platform.Webhook

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :developer_id]
  @optional_fields [:description, :logo_url, :website_url, :callback_urls, :scopes, :status]

  def changeset(application, attrs) do
    application
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_url(:logo_url)
    |> validate_url(:website_url)
    |> validate_callback_urls()
    |> validate_scopes()
    |> validate_inclusion(:status, @statuses)
    |> generate_api_credentials()
    |> foreign_key_constraint(:developer_id)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
          []
        _ ->
          [{field, "must be a valid URL"}]
      end
    end)
  end

  defp validate_callback_urls(changeset) do
    validate_change(changeset, :callback_urls, fn :callback_urls, urls ->
      Enum.flat_map(urls, fn url ->
        case URI.parse(url) do
          %URI{scheme: "https", host: host} when not is_nil(host) -> []
          _ -> [callback_urls: "must all be valid HTTPS URLs"]
        end
      end)
    end)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      invalid = scopes -- @scopes
      if invalid == [] do
        []
      else
        [scopes: "contains invalid scopes: #{inspect(invalid)}"]
      end
    end)
  end

  defp generate_api_credentials(changeset) do
    if get_change(changeset, :developer_id) && !get_field(changeset, :api_key_hash) do
      api_key = generate_key("ck_")
      api_secret = generate_key("cs_")

      changeset
      |> put_change(:api_key, api_key)  # Return once, then discard
      |> put_change(:api_key_hash, hash_key(api_key))
      |> put_change(:api_secret_hash, hash_key(api_secret))
    else
      changeset
    end
  end

  defp generate_key(prefix) do
    prefix <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
  end

  defp hash_key(key) do
    :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)
  end

  def valid_scopes, do: @scopes
end
```

### 8.3 Application Users (App-User Authorization)

```elixir
defmodule Conezia.Platform.ApplicationUser do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "application_users" do
    field :external_user_id, :string  # User ID in the third-party app
    field :granted_scopes, {:array, :string}, default: []
    field :authorized_at, :utc_datetime_usec
    field :last_accessed_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :application, Conezia.Platform.Application
    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:application_id, :user_id]
  @optional_fields [:external_user_id, :granted_scopes, :authorized_at, :last_accessed_at, :revoked_at]

  def changeset(app_user, attrs) do
    app_user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_scopes()
    |> put_authorized_at()
    |> unique_constraint([:application_id, :user_id])
    |> foreign_key_constraint(:application_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_scopes(changeset) do
    valid_scopes = Conezia.Platform.Application.valid_scopes()
    validate_change(changeset, :granted_scopes, fn :granted_scopes, scopes ->
      invalid = scopes -- valid_scopes
      if invalid == [], do: [], else: [granted_scopes: "contains invalid scopes"]
    end)
  end

  defp put_authorized_at(changeset) do
    if get_change(changeset, :application_id) && !get_field(changeset, :authorized_at) do
      put_change(changeset, :authorized_at, DateTime.utc_now())
    else
      changeset
    end
  end

  def update_access_changeset(app_user) do
    change(app_user, last_accessed_at: DateTime.utc_now())
  end

  def revoke_changeset(app_user) do
    change(app_user, revoked_at: DateTime.utc_now())
  end
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreateApplicationUsers do
  use Ecto.Migration

  def change do
    create table(:application_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :external_user_id, :string, size: 255
      add :granted_scopes, {:array, :string}, default: []
      add :authorized_at, :utc_datetime_usec
      add :last_accessed_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:application_users, [:application_id, :user_id])
    create index(:application_users, [:user_id])
    create index(:application_users, [:application_id, :authorized_at])
  end
end
```

### 8.4 Webhooks

```elixir
defmodule Conezia.Platform.Webhook do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @events ~w(entity.created entity.updated entity.deleted
             communication.sent reminder.due reminder.completed
             import.completed)
  @statuses ~w(active paused failed)

  schema "webhooks" do
    field :url, :string
    field :events, {:array, :string}, default: []
    field :secret, :string
    field :status, :string, default: "active"
    field :last_triggered_at, :utc_datetime_usec
    field :failure_count, :integer, default: 0

    belongs_to :application, Conezia.Platform.Application
    has_many :deliveries, Conezia.Platform.WebhookDelivery

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:url, :events, :application_id]
  @optional_fields [:status, :last_triggered_at, :failure_count]

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_url(:url)
    |> validate_events()
    |> validate_inclusion(:status, @statuses)
    |> generate_secret()
    |> foreign_key_constraint(:application_id)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: "https", host: host} when not is_nil(host) ->
          []
        _ ->
          [{field, "must be a valid HTTPS URL"}]
      end
    end)
  end

  defp validate_events(changeset) do
    validate_change(changeset, :events, fn :events, events ->
      if events == [] do
        [events: "must have at least one event"]
      else
        invalid = events -- @events
        if invalid == [] do
          []
        else
          [events: "contains invalid events: #{inspect(invalid)}"]
        end
      end
    end)
  end

  defp generate_secret(changeset) do
    if !get_field(changeset, :secret) do
      secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      put_change(changeset, :secret, secret)
    else
      changeset
    end
  end

  def valid_events, do: @events
end
```

**Migration:**

```elixir
defmodule Conezia.Repo.Migrations.CreatePlatformTables do
  use Ecto.Migration

  def change do
    create table(:import_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :source, :string, size: 32, null: false
      add :status, :string, size: 16, default: "pending"
      add :total_records, :integer, default: 0
      add :processed_records, :integer, default: 0
      add :created_records, :integer, default: 0
      add :merged_records, :integer, default: 0
      add :skipped_records, :integer, default: 0
      add :error_log, {:array, :map}, default: []
      add :file_path, :string, size: 512
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:import_jobs, [:user_id, :status])

    create table(:applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :developer_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 100, null: false
      add :description, :text
      add :logo_url, :string, size: 2048
      add :website_url, :string, size: 2048
      add :callback_urls, {:array, :string}, default: []
      add :api_key_hash, :string, size: 64, null: false
      add :api_secret_hash, :string, size: 64, null: false
      add :scopes, {:array, :string}, default: []
      add :status, :string, size: 16, default: "pending"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:applications, [:developer_id])
    create unique_index(:applications, [:api_key_hash])

    create table(:application_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :external_user_id, :string, size: 255
      add :granted_scopes, {:array, :string}, default: []
      add :authorized_at, :utc_datetime_usec
      add :last_accessed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:application_users, [:application_id, :user_id])
    create index(:application_users, [:user_id])

    create table(:webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all), null: false
      add :url, :string, size: 2048, null: false
      add :events, {:array, :string}, default: []
      add :secret, :string, size: 64, null: false
      add :status, :string, size: 16, default: "active"
      add :last_triggered_at, :utc_datetime_usec
      add :failure_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:webhooks, [:application_id, :status])

    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :webhook_id, references(:webhooks, type: :binary_id, on_delete: :delete_all), null: false
      add :event_type, :string, size: 64, null: false
      add :payload, :map, null: false
      add :response_status, :integer
      add :response_body, :text
      add :delivered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:webhook_deliveries, [:webhook_id, :inserted_at])
  end
end
```

---

## 9. Database Extensions & Setup

### 9.1 Required Extensions

```elixir
defmodule Conezia.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def up do
    # Case-insensitive text for emails
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    # UUID generation
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

    # Trigram for fuzzy search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Full-text search dictionaries
    execute "CREATE EXTENSION IF NOT EXISTS unaccent"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS unaccent"
    execute "DROP EXTENSION IF EXISTS pg_trgm"
    execute "DROP EXTENSION IF EXISTS \"uuid-ossp\""
    execute "DROP EXTENSION IF EXISTS citext"
  end
end
```

### 9.2 Full-Text Search Configuration

```elixir
defmodule Conezia.Repo.Migrations.SetupFullTextSearch do
  use Ecto.Migration

  def up do
    # Create custom text search configuration
    execute """
    CREATE TEXT SEARCH CONFIGURATION conezia_search (COPY = simple);
    ALTER TEXT SEARCH CONFIGURATION conezia_search
      ALTER MAPPING FOR hword, hword_part, word
      WITH unaccent, simple;
    """

    # Add tsvector column to entities for full-text search
    execute """
    ALTER TABLE entities ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      setweight(to_tsvector('conezia_search', coalesce(name, '')), 'A') ||
      setweight(to_tsvector('conezia_search', coalesce(description, '')), 'B')
    ) STORED;
    """

    execute "CREATE INDEX entities_search_idx ON entities USING gin(search_vector);"
  end

  def down do
    execute "DROP INDEX IF EXISTS entities_search_idx;"
    execute "ALTER TABLE entities DROP COLUMN IF EXISTS search_vector;"
    execute "DROP TEXT SEARCH CONFIGURATION IF EXISTS conezia_search;"
  end
end
```

---

## 10. Index Summary

### 10.1 Primary Indexes

| Table | Index | Columns | Type |
|-------|-------|---------|------|
| users | unique | email | btree |
| entities | composite | owner_id, type | btree |
| entities | composite | owner_id, archived_at | btree |
| entities | fts | search_vector | gin |
| entities | trigram | name | gin |
| relationships | unique | user_id, entity_id | btree |
| identifiers | composite | type, value_hash | btree |
| tags | unique | user_id, name | btree |
| groups | unique | user_id, name | btree |
| conversations | composite | user_id, is_archived | btree |
| communications | index | sent_at | btree |
| reminders | partial | due_at WHERE pending | btree |
| activity_logs | composite | user_id, inserted_at | btree |

### 10.2 Foreign Key Indexes

All foreign keys have corresponding indexes for efficient joins and cascading deletes.

---

*Document Version: 1.0*
*Created: 2026-01-17*
