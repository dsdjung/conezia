# Conezia Validation Rules

## 1. Overview

This document defines comprehensive validation rules for all data inputs in Conezia. Validation is enforced at multiple layers: API request validation, Ecto changeset validation, and database constraints.

### 1.1 Validation Philosophy

1. **Validate Early**: Catch errors at the API boundary before hitting the database
2. **Validate Completely**: Every field has explicit validation rules
3. **Fail Fast**: Return all validation errors at once, not one at a time
4. **Meaningful Errors**: Provide actionable error messages

### 1.2 Validation Layers

```
┌─────────────────────────────────────────────────┐
│  Layer 1: API Request Validation                │
│  - JSON schema validation                       │
│  - Required fields check                        │
│  - Type coercion                                │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  Layer 2: Ecto Changeset Validation             │
│  - Business rule validation                     │
│  - Format validation                            │
│  - Cross-field validation                       │
│  - Uniqueness checks (with DB)                  │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  Layer 3: Database Constraints                  │
│  - NOT NULL constraints                         │
│  - UNIQUE constraints                           │
│  - FOREIGN KEY constraints                      │
│  - CHECK constraints                            │
└─────────────────────────────────────────────────┘
```

---

## 2. User Validation

### 2.1 User Schema Validation

```elixir
defmodule Conezia.Accounts.UserValidator do
  import Ecto.Changeset

  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  @password_rules [
    min_length: 8,
    max_length: 72,
    require_lowercase: true,
    require_uppercase: true,
    require_number: true,
    require_special: false
  ]

  def validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, @email_regex, message: "must be a valid email address")
    |> validate_length(:email, max: 254)
    |> update_change(:email, &String.downcase(&1))
    |> unsafe_validate_unique(:email, Conezia.Repo)
    |> unique_constraint(:email, message: "has already been taken")
  end

  def validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password,
        min: @password_rules[:min_length],
        max: @password_rules[:max_length]
       )
    |> validate_password_complexity()
  end

  defp validate_password_complexity(changeset) do
    changeset
    |> validate_format(:password, ~r/[a-z]/,
        message: "must contain at least one lowercase letter")
    |> validate_format(:password, ~r/[A-Z]/,
        message: "must contain at least one uppercase letter")
    |> validate_format(:password, ~r/[0-9]/,
        message: "must contain at least one number")
  end

  def validate_name(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 255)
    |> validate_format(:name, ~r/^[\p{L}\p{M}\s\-'\.]+$/u,
        message: "can only contain letters, spaces, hyphens, apostrophes, and periods")
  end

  def validate_timezone(changeset) do
    validate_change(changeset, :timezone, fn :timezone, tz ->
      if tz in Tzdata.zone_list() do
        []
      else
        [timezone: "must be a valid IANA timezone (e.g., 'America/New_York')"]
      end
    end)
  end

  def validate_avatar_url(changeset) do
    changeset
    |> validate_length(:avatar_url, max: 2048)
    |> validate_url(:avatar_url)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host}
            when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []
        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end
end
```

### 2.2 User Validation Rules Summary

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `email` | string | Yes | Valid email format, max 254 chars, unique, lowercase |
| `password` | string | Yes (registration) | 8-72 chars, 1 lowercase, 1 uppercase, 1 number |
| `name` | string | No | 1-255 chars, letters/spaces/hyphens/apostrophes only |
| `avatar_url` | string | No | Valid HTTP(S) URL, max 2048 chars |
| `timezone` | string | No | Valid IANA timezone |
| `settings` | map | No | Valid JSON object |

---

## 3. Entity Validation

### 3.1 Entity Schema Validation

```elixir
defmodule Conezia.Entities.EntityValidator do
  import Ecto.Changeset

  @entity_types ~w(person organization service thing animal abstract)

  def validate_type(changeset) do
    changeset
    |> validate_required([:type])
    |> validate_inclusion(:type, @entity_types,
        message: "must be one of: #{Enum.join(@entity_types, ", ")}")
  end

  def validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_not_blank(:name)
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 10_000)
  end

  def validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      cond do
        !is_map(metadata) ->
          [metadata: "must be a valid JSON object"]
        byte_size(Jason.encode!(metadata)) > 65_536 ->
          [metadata: "must be less than 64KB when serialized"]
        true ->
          []
      end
    end)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end
end
```

### 3.2 Entity Validation Rules Summary

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `type` | enum | Yes | One of: person, organization, service, thing, animal, abstract |
| `name` | string | Yes | 1-255 chars, not blank |
| `description` | string | No | Max 10,000 chars |
| `avatar_url` | string | No | Valid HTTP(S) URL, max 2048 chars |
| `metadata` | map | No | Valid JSON, max 64KB serialized |
| `owner_id` | uuid | Yes | Must reference valid user |

---

## 4. Relationship Validation

### 4.1 Relationship Schema Validation

```elixir
defmodule Conezia.Entities.RelationshipValidator do
  import Ecto.Changeset

  @relationship_types ~w(friend family colleague client vendor acquaintance service_provider other)
  @strength_levels ~w(close regular acquaintance)
  @statuses ~w(active inactive archived)

  def validate_type(changeset) do
    validate_inclusion(changeset, :type, @relationship_types,
      message: "must be one of: #{Enum.join(@relationship_types, ", ")}")
  end

  def validate_strength(changeset) do
    changeset
    |> validate_inclusion(:strength, @strength_levels,
        message: "must be one of: #{Enum.join(@strength_levels, ", ")}")
  end

  def validate_status(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses,
        message: "must be one of: #{Enum.join(@statuses, ", ")}")
  end

  def validate_health_threshold(changeset) do
    changeset
    |> validate_number(:health_threshold_days,
        greater_than: 0,
        less_than_or_equal_to: 365,
        message: "must be between 1 and 365 days")
  end

  def validate_started_at(changeset) do
    validate_change(changeset, :started_at, fn :started_at, date ->
      cond do
        Date.compare(date, Date.utc_today()) == :gt ->
          [started_at: "cannot be in the future"]
        Date.compare(date, ~D[1900-01-01]) == :lt ->
          [started_at: "must be after 1900-01-01"]
        true ->
          []
      end
    end)
  end

  def validate_notes(changeset) do
    validate_length(changeset, :notes, max: 5000)
  end

  def validate_unique_relationship(changeset) do
    changeset
    |> unique_constraint([:user_id, :entity_id],
        message: "relationship already exists for this entity")
  end
end
```

### 4.2 Relationship Validation Rules Summary

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `user_id` | uuid | Yes | Must reference valid user |
| `entity_id` | uuid | Yes | Must reference valid entity |
| `type` | enum | No | One of: friend, family, colleague, client, vendor, acquaintance, service_provider, other |
| `strength` | enum | No | One of: close, regular, acquaintance (default: regular) |
| `status` | enum | No | One of: active, inactive, archived (default: active) |
| `health_threshold_days` | integer | No | 1-365 (default: 30) |
| `started_at` | date | No | Not in future, after 1900-01-01 |
| `notes` | string | No | Max 5,000 chars |

---

## 5. Identifier Validation

### 5.1 Identifier Schema Validation

```elixir
defmodule Conezia.Entities.IdentifierValidator do
  import Ecto.Changeset

  @identifier_types ~w(phone email ssn government_id account_number social_handle website)
  @sensitive_types ~w(ssn government_id account_number)

  # E.164 phone format: +[country code][number], 7-15 digits total
  @phone_regex ~r/^\+[1-9]\d{6,14}$/

  # Standard email regex (RFC 5322 simplified)
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  # US SSN format: XXX-XX-XXXX
  @ssn_regex ~r/^\d{3}-\d{2}-\d{4}$/

  # Social handle: alphanumeric with underscore, optionally prefixed with @
  @social_handle_regex ~r/^@?[a-zA-Z0-9_]{1,50}$/

  def validate_type(changeset) do
    changeset
    |> validate_required([:type])
    |> validate_inclusion(:type, @identifier_types,
        message: "must be one of: #{Enum.join(@identifier_types, ", ")}")
  end

  def validate_value(changeset) do
    changeset
    |> validate_required([:value])
    |> validate_value_by_type()
  end

  defp validate_value_by_type(changeset) do
    type = get_field(changeset, :type)
    value = get_change(changeset, :value)

    if value && type do
      case type do
        "phone" -> validate_phone_value(changeset, value)
        "email" -> validate_email_value(changeset, value)
        "ssn" -> validate_ssn_value(changeset, value)
        "government_id" -> validate_government_id_value(changeset, value)
        "account_number" -> validate_account_number_value(changeset, value)
        "social_handle" -> validate_social_handle_value(changeset, value)
        "website" -> validate_website_value(changeset, value)
        _ -> changeset
      end
    else
      changeset
    end
  end

  defp validate_phone_value(changeset, value) do
    # Normalize phone: remove spaces, dashes, parentheses
    normalized = String.replace(value, ~r/[\s\-\(\)]+/, "")

    if Regex.match?(@phone_regex, normalized) do
      put_change(changeset, :value, normalized)
    else
      add_error(changeset, :value,
        "must be in E.164 format (e.g., +12025551234)")
    end
  end

  defp validate_email_value(changeset, value) do
    normalized = String.downcase(String.trim(value))

    cond do
      String.length(normalized) > 254 ->
        add_error(changeset, :value, "must be at most 254 characters")
      !Regex.match?(@email_regex, normalized) ->
        add_error(changeset, :value, "must be a valid email address")
      true ->
        put_change(changeset, :value, normalized)
    end
  end

  defp validate_ssn_value(changeset, value) do
    if Regex.match?(@ssn_regex, value) do
      # Additional validation: check for invalid SSNs
      [area, group, serial] = String.split(value, "-")

      cond do
        area == "000" or area == "666" or String.starts_with?(area, "9") ->
          add_error(changeset, :value, "contains invalid area number")
        group == "00" ->
          add_error(changeset, :value, "contains invalid group number")
        serial == "0000" ->
          add_error(changeset, :value, "contains invalid serial number")
        true ->
          changeset
      end
    else
      add_error(changeset, :value, "must be in format XXX-XX-XXXX")
    end
  end

  defp validate_government_id_value(changeset, value) do
    # Basic validation - alphanumeric with some special chars
    if String.length(value) > 0 and String.length(value) <= 50 and
       Regex.match?(~r/^[a-zA-Z0-9\-\s]+$/, value) do
      changeset
    else
      add_error(changeset, :value,
        "must be 1-50 characters, alphanumeric with hyphens and spaces only")
    end
  end

  defp validate_account_number_value(changeset, value) do
    # Basic validation - alphanumeric
    if String.length(value) > 0 and String.length(value) <= 50 and
       Regex.match?(~r/^[a-zA-Z0-9\-]+$/, value) do
      changeset
    else
      add_error(changeset, :value,
        "must be 1-50 characters, alphanumeric with hyphens only")
    end
  end

  defp validate_social_handle_value(changeset, value) do
    normalized = if String.starts_with?(value, "@"), do: value, else: "@#{value}"

    if Regex.match?(@social_handle_regex, String.slice(normalized, 1..-1//1)) do
      put_change(changeset, :value, normalized)
    else
      add_error(changeset, :value,
        "must be 1-50 alphanumeric characters or underscores")
    end
  end

  defp validate_website_value(changeset, value) do
    # Add protocol if missing
    normalized = if String.starts_with?(value, "http"),
      do: value,
      else: "https://#{value}"

    case URI.parse(normalized) do
      %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if String.length(normalized) <= 2048 do
          put_change(changeset, :value, normalized)
        else
          add_error(changeset, :value, "must be at most 2048 characters")
        end
      _ ->
        add_error(changeset, :value, "must be a valid URL")
    end
  end

  def validate_label(changeset) do
    changeset
    |> validate_length(:label, max: 64)
    |> validate_format(:label, ~r/^[\p{L}\p{N}\s\-]+$/u,
        message: "can only contain letters, numbers, spaces, and hyphens")
  end

  def sensitive_type?(type), do: type in @sensitive_types
end
```

### 5.2 Identifier Validation Rules Summary

| Type | Format | Example | Normalization |
|------|--------|---------|---------------|
| `phone` | E.164 | +12025551234 | Remove spaces, dashes, parens |
| `email` | RFC 5322 | user@example.com | Lowercase, trim |
| `ssn` | XXX-XX-XXXX | 123-45-6789 | None (encrypted) |
| `government_id` | Alphanumeric | A12345678 | None (encrypted) |
| `account_number` | Alphanumeric | ACC-123456 | None (encrypted) |
| `social_handle` | @username | @johndoe | Add @ prefix if missing |
| `website` | URL | https://example.com | Add https:// if missing |

---

## 6. Communication Validation

### 6.1 Communication Schema Validation

```elixir
defmodule Conezia.Communications.CommunicationValidator do
  import Ecto.Changeset

  @channels ~w(internal email sms whatsapp telegram phone)
  @directions ~w(inbound outbound)
  @max_content_length 100_000
  @max_attachments 10
  @max_attachment_size 50 * 1024 * 1024  # 50 MB

  def validate_channel(changeset) do
    changeset
    |> validate_required([:channel])
    |> validate_inclusion(:channel, @channels,
        message: "must be one of: #{Enum.join(@channels, ", ")}")
  end

  def validate_direction(changeset) do
    changeset
    |> validate_required([:direction])
    |> validate_inclusion(:direction, @directions,
        message: "must be one of: #{Enum.join(@directions, ", ")}")
  end

  def validate_content(changeset) do
    changeset
    |> validate_required([:content])
    |> validate_length(:content,
        min: 1,
        max: @max_content_length,
        message: "must be between 1 and #{@max_content_length} characters")
    |> validate_not_blank(:content)
  end

  def validate_attachments(changeset) do
    validate_change(changeset, :attachments, fn :attachments, attachments ->
      cond do
        length(attachments) > @max_attachments ->
          [attachments: "cannot have more than #{@max_attachments} attachments"]
        true ->
          validate_each_attachment(attachments)
      end
    end)
  end

  defp validate_each_attachment(attachments) do
    attachments
    |> Enum.with_index()
    |> Enum.flat_map(fn {attachment, index} ->
      errors = []

      errors = if !Map.has_key?(attachment, "id"),
        do: [{:attachments, "attachment #{index + 1} must have an id"} | errors],
        else: errors

      errors = if !Map.has_key?(attachment, "filename"),
        do: [{:attachments, "attachment #{index + 1} must have a filename"} | errors],
        else: errors

      errors = if !Map.has_key?(attachment, "mime_type"),
        do: [{:attachments, "attachment #{index + 1} must have a mime_type"} | errors],
        else: errors

      errors
    end)
  end

  def validate_sent_at(changeset) do
    validate_change(changeset, :sent_at, fn :sent_at, sent_at ->
      # Allow up to 1 hour in the future (for scheduled sends)
      max_future = DateTime.add(DateTime.utc_now(), 3600, :second)

      if DateTime.compare(sent_at, max_future) == :gt do
        [sent_at: "cannot be more than 1 hour in the future"]
      else
        []
      end
    end)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end
end
```

### 6.2 Communication Validation Rules Summary

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `channel` | enum | Yes | One of: internal, email, sms, whatsapp, telegram, phone |
| `direction` | enum | Yes | One of: inbound, outbound |
| `content` | string | Yes | 1-100,000 chars, not blank |
| `attachments` | array | No | Max 10 items, each must have id, filename, mime_type |
| `sent_at` | datetime | No | Not more than 1 hour in future |
| `user_id` | uuid | Yes | Must reference valid user |
| `entity_id` | uuid | Yes | Must reference valid entity |

---

## 7. Reminder Validation

### 7.1 Reminder Schema Validation

```elixir
defmodule Conezia.Reminders.ReminderValidator do
  import Ecto.Changeset

  @reminder_types ~w(follow_up birthday anniversary custom health_alert event)
  @notification_channels ~w(in_app email push)
  @recurrence_frequencies ~w(daily weekly monthly yearly)

  def validate_type(changeset) do
    changeset
    |> validate_required([:type])
    |> validate_inclusion(:type, @reminder_types,
        message: "must be one of: #{Enum.join(@reminder_types, ", ")}")
  end

  def validate_title(changeset) do
    changeset
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_not_blank(:title)
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 2000)
  end

  def validate_due_at(changeset, opts \\ []) do
    allow_past = Keyword.get(opts, :allow_past, false)

    changeset
    |> validate_required([:due_at])
    |> validate_due_at_constraints(allow_past)
  end

  defp validate_due_at_constraints(changeset, allow_past) do
    validate_change(changeset, :due_at, fn :due_at, due_at ->
      now = DateTime.utc_now()
      max_future = DateTime.add(now, 365 * 5 * 24 * 3600, :second)  # 5 years

      cond do
        !allow_past && DateTime.compare(due_at, now) != :gt ->
          [due_at: "must be in the future"]
        DateTime.compare(due_at, max_future) == :gt ->
          [due_at: "cannot be more than 5 years in the future"]
        true ->
          []
      end
    end)
  end

  def validate_notification_channels(changeset) do
    changeset
    |> validate_required([:notification_channels])
    |> validate_change(:notification_channels, fn :notification_channels, channels ->
      cond do
        !is_list(channels) ->
          [notification_channels: "must be a list"]
        channels == [] ->
          [notification_channels: "must have at least one channel"]
        invalid = channels -- @notification_channels; invalid != [] ->
          [notification_channels: "contains invalid channels: #{inspect(invalid)}"]
        true ->
          []
      end
    end)
  end

  def validate_recurrence_rule(changeset) do
    validate_change(changeset, :recurrence_rule, fn :recurrence_rule, rule ->
      case rule do
        nil -> []
        %{} -> validate_recurrence_rule_structure(rule)
        _ -> [recurrence_rule: "must be a valid recurrence rule object"]
      end
    end)
  end

  defp validate_recurrence_rule_structure(rule) do
    errors = []

    # Validate freq (required for recurrence)
    errors = case Map.get(rule, "freq") do
      nil -> [{:recurrence_rule, "must have a 'freq' field"} | errors]
      freq when freq in @recurrence_frequencies -> errors
      _ -> [{:recurrence_rule, "freq must be one of: #{Enum.join(@recurrence_frequencies, ", ")}"} | errors]
    end

    # Validate interval if present
    errors = case Map.get(rule, "interval") do
      nil -> errors
      interval when is_integer(interval) and interval > 0 and interval <= 365 -> errors
      _ -> [{:recurrence_rule, "interval must be a positive integer up to 365"} | errors]
    end

    # Validate count if present
    errors = case Map.get(rule, "count") do
      nil -> errors
      count when is_integer(count) and count > 0 and count <= 1000 -> errors
      _ -> [{:recurrence_rule, "count must be a positive integer up to 1000"} | errors]
    end

    # Validate until if present
    errors = case Map.get(rule, "until") do
      nil -> errors
      until_str ->
        case DateTime.from_iso8601(until_str) do
          {:ok, _, _} -> errors
          _ -> [{:recurrence_rule, "until must be a valid ISO8601 datetime"} | errors]
        end
    end

    errors
  end

  def validate_snooze(changeset) do
    validate_change(changeset, :snoozed_until, fn :snoozed_until, snoozed_until ->
      now = DateTime.utc_now()
      max_snooze = DateTime.add(now, 30 * 24 * 3600, :second)  # 30 days

      cond do
        DateTime.compare(snoozed_until, now) != :gt ->
          [snoozed_until: "must be in the future"]
        DateTime.compare(snoozed_until, max_snooze) == :gt ->
          [snoozed_until: "cannot snooze more than 30 days"]
        true ->
          []
      end
    end)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end
end
```

### 7.2 Reminder Validation Rules Summary

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `type` | enum | Yes | One of: follow_up, birthday, anniversary, custom, health_alert, event |
| `title` | string | Yes | 1-255 chars, not blank |
| `description` | string | No | Max 2,000 chars |
| `due_at` | datetime | Yes | Must be in future, max 5 years |
| `notification_channels` | array | Yes | At least one of: in_app, email, push |
| `recurrence_rule` | map | No | Valid RRULE with freq, optional interval/count/until |
| `snoozed_until` | datetime | No | Must be future, max 30 days |
| `user_id` | uuid | Yes | Must reference valid user |
| `entity_id` | uuid | No | Must reference valid entity if provided |

---

## 8. Tag & Group Validation

### 8.1 Tag Validation

```elixir
defmodule Conezia.Entities.TagValidator do
  import Ecto.Changeset

  @colors ~w(red orange yellow green blue purple pink gray)
  @max_tags_per_user 100

  def validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_format(:name, ~r/^[\p{L}\p{N}\s\-_]+$/u,
        message: "can only contain letters, numbers, spaces, hyphens, and underscores")
    |> validate_not_blank(:name)
    |> unique_constraint([:user_id, :name],
        message: "tag with this name already exists")
  end

  def validate_color(changeset) do
    validate_inclusion(changeset, :color, @colors,
      message: "must be one of: #{Enum.join(@colors, ", ")}")
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 255)
  end

  def validate_tag_limit(user_id) do
    count = Conezia.Repo.aggregate(
      from(t in Conezia.Entities.Tag, where: t.user_id == ^user_id),
      :count
    )

    if count >= @max_tags_per_user do
      {:error, "maximum of #{@max_tags_per_user} tags allowed"}
    else
      :ok
    end
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end
end
```

### 8.2 Group Validation

```elixir
defmodule Conezia.Entities.GroupValidator do
  import Ecto.Changeset

  @valid_rule_fields ~w(type tags relationship_type relationship_status last_interaction_days)
  @max_groups_per_user 50

  def validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_not_blank(:name)
    |> unique_constraint([:user_id, :name],
        message: "group with this name already exists")
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 500)
  end

  def validate_smart_rules(changeset) do
    is_smart = get_field(changeset, :is_smart)
    rules = get_field(changeset, :rules)

    cond do
      is_smart && (is_nil(rules) || rules == %{}) ->
        add_error(changeset, :rules, "is required for smart groups")
      is_smart ->
        validate_rules_structure(changeset, rules)
      !is_smart && rules && rules != %{} ->
        add_error(changeset, :rules, "should not be provided for non-smart groups")
      true ->
        changeset
    end
  end

  defp validate_rules_structure(changeset, rules) do
    errors = []

    # Check for invalid rule fields
    invalid_fields = Map.keys(rules) -- @valid_rule_fields
    errors = if invalid_fields != [] do
      [{:rules, "contains invalid fields: #{Enum.join(invalid_fields, ", ")}"} | errors]
    else
      errors
    end

    # Validate last_interaction_days if present
    errors = case Map.get(rules, "last_interaction_days") do
      nil -> errors
      days when is_integer(days) and days > 0 and days <= 365 -> errors
      _ -> [{:rules, "last_interaction_days must be 1-365"} | errors]
    end

    # Validate tags if present
    errors = case Map.get(rules, "tags") do
      nil -> errors
      tags when is_list(tags) -> errors
      _ -> [{:rules, "tags must be a list"} | errors]
    end

    Enum.reduce(errors, changeset, fn {field, msg}, cs ->
      add_error(cs, field, msg)
    end)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end
end
```

---

## 9. Attachment Validation

```elixir
defmodule Conezia.Attachments.AttachmentValidator do
  import Ecto.Changeset

  @max_file_size 50 * 1024 * 1024  # 50 MB
  @max_filename_length 255

  @allowed_mime_types %{
    # Images
    "image/jpeg" => [".jpg", ".jpeg"],
    "image/png" => [".png"],
    "image/gif" => [".gif"],
    "image/webp" => [".webp"],
    # Documents
    "application/pdf" => [".pdf"],
    "text/plain" => [".txt"],
    "text/csv" => [".csv"],
    # Office documents
    "application/msword" => [".doc"],
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => [".docx"],
    "application/vnd.ms-excel" => [".xls"],
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => [".xlsx"],
    # Archives
    "application/zip" => [".zip"]
  }

  def validate_filename(changeset) do
    changeset
    |> validate_required([:filename])
    |> validate_length(:filename, min: 1, max: @max_filename_length)
    |> validate_filename_safety()
  end

  defp validate_filename_safety(changeset) do
    validate_change(changeset, :filename, fn :filename, filename ->
      cond do
        # Prevent directory traversal
        String.contains?(filename, ["../", "..\\"]) ->
          [filename: "cannot contain directory traversal sequences"]
        # Prevent null bytes
        String.contains?(filename, <<0>>) ->
          [filename: "cannot contain null bytes"]
        # Check for valid characters
        !Regex.match?(~r/^[\w\-\. ]+$/u, filename) ->
          [filename: "contains invalid characters"]
        true ->
          []
      end
    end)
  end

  def validate_mime_type(changeset) do
    changeset
    |> validate_required([:mime_type])
    |> validate_inclusion(:mime_type, Map.keys(@allowed_mime_types),
        message: "file type not allowed")
    |> validate_extension_matches_mime()
  end

  defp validate_extension_matches_mime(changeset) do
    mime_type = get_field(changeset, :mime_type)
    filename = get_field(changeset, :filename)

    if mime_type && filename do
      allowed_extensions = Map.get(@allowed_mime_types, mime_type, [])
      extension = Path.extname(filename) |> String.downcase()

      if extension in allowed_extensions do
        changeset
      else
        add_error(changeset, :filename,
          "extension does not match mime type #{mime_type}")
      end
    else
      changeset
    end
  end

  def validate_size(changeset) do
    changeset
    |> validate_required([:size_bytes])
    |> validate_number(:size_bytes,
        greater_than: 0,
        less_than_or_equal_to: @max_file_size,
        message: "must be between 1 byte and #{div(@max_file_size, 1024 * 1024)} MB")
  end

  def validate_parent_association(changeset) do
    entity_id = get_field(changeset, :entity_id)
    interaction_id = get_field(changeset, :interaction_id)
    communication_id = get_field(changeset, :communication_id)

    if entity_id || interaction_id || communication_id do
      changeset
    else
      add_error(changeset, :entity_id,
        "at least one of entity_id, interaction_id, or communication_id is required")
    end
  end

  def allowed_mime_types, do: @allowed_mime_types
  def max_file_size, do: @max_file_size
end
```

---

## 10. Import Validation

```elixir
defmodule Conezia.Imports.ImportValidator do
  import Ecto.Changeset

  @sources ~w(google csv vcard linkedin icloud outlook)
  @max_file_size 10 * 1024 * 1024  # 10 MB for import files
  @max_records_per_import 10_000

  def validate_source(changeset) do
    changeset
    |> validate_required([:source])
    |> validate_inclusion(:source, @sources,
        message: "must be one of: #{Enum.join(@sources, ", ")}")
  end

  def validate_file(file_path, source) do
    cond do
      !File.exists?(file_path) ->
        {:error, "file not found"}
      File.stat!(file_path).size > @max_file_size ->
        {:error, "file exceeds maximum size of #{div(@max_file_size, 1024 * 1024)} MB"}
      true ->
        validate_file_content(file_path, source)
    end
  end

  defp validate_file_content(file_path, "csv") do
    case File.read(file_path) do
      {:ok, content} ->
        case NimbleCSV.RFC4180.parse_string(content, skip_headers: false) do
          {:ok, rows} when length(rows) > @max_records_per_import ->
            {:error, "file contains more than #{@max_records_per_import} records"}
          {:ok, rows} when length(rows) > 1 ->
            {:ok, length(rows) - 1}  # Subtract header row
          {:ok, _} ->
            {:error, "file must contain at least one data row"}
          {:error, _} ->
            {:error, "invalid CSV format"}
        end
      {:error, _} ->
        {:error, "could not read file"}
    end
  end

  defp validate_file_content(file_path, "vcard") do
    case File.read(file_path) do
      {:ok, content} ->
        vcard_count = content
          |> String.split("BEGIN:VCARD")
          |> length()
          |> Kernel.-(1)

        cond do
          vcard_count == 0 ->
            {:error, "no valid vCard entries found"}
          vcard_count > @max_records_per_import ->
            {:error, "file contains more than #{@max_records_per_import} contacts"}
          true ->
            {:ok, vcard_count}
        end
      {:error, _} ->
        {:error, "could not read file"}
    end
  end

  defp validate_file_content(_file_path, _source) do
    {:ok, :unknown}
  end

  def validate_field_mapping(mapping, source) do
    required_fields = case source do
      "csv" -> ["name"]
      "vcard" -> []  # vCard has structured fields
      _ -> []
    end

    mapped_fields = Map.values(mapping)
    missing = required_fields -- mapped_fields

    if missing == [] do
      :ok
    else
      {:error, "missing required field mappings: #{Enum.join(missing, ", ")}"}
    end
  end
end
```

---

## 11. Platform Validation

### 11.1 Application Validation

```elixir
defmodule Conezia.Platform.ApplicationValidator do
  import Ecto.Changeset

  @statuses ~w(pending approved suspended)
  @valid_scopes ~w(
    read:entities write:entities delete:entities
    read:communications write:communications
    read:reminders write:reminders
    read:profile write:profile
  )

  def validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:name, ~r/^[\p{L}\p{N}\s\-_]+$/u,
        message: "can only contain letters, numbers, spaces, hyphens, and underscores")
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 1000)
  end

  def validate_urls(changeset) do
    changeset
    |> validate_url(:logo_url)
    |> validate_url(:website_url)
    |> validate_callback_urls()
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host}
            when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []
        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end

  defp validate_callback_urls(changeset) do
    validate_change(changeset, :callback_urls, fn :callback_urls, urls ->
      if is_list(urls) do
        urls
        |> Enum.with_index()
        |> Enum.flat_map(fn {url, index} ->
          case URI.parse(url) do
            %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
              []
            _ ->
              [callback_urls: "URL at position #{index + 1} must be a valid HTTPS URL"]
          end
        end)
      else
        [callback_urls: "must be a list of URLs"]
      end
    end)
  end

  def validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      if is_list(scopes) do
        invalid = scopes -- @valid_scopes
        if invalid == [] do
          []
        else
          [scopes: "contains invalid scopes: #{Enum.join(invalid, ", ")}"]
        end
      else
        [scopes: "must be a list of scope strings"]
      end
    end)
  end

  def validate_status(changeset) do
    validate_inclusion(changeset, :status, @statuses)
  end

  def valid_scopes, do: @valid_scopes
end
```

### 11.2 Webhook Validation

```elixir
defmodule Conezia.Platform.WebhookValidator do
  import Ecto.Changeset

  @valid_events ~w(
    entity.created entity.updated entity.deleted
    communication.sent
    reminder.due reminder.completed
    import.completed
  )
  @statuses ~w(active paused failed)
  @max_webhooks_per_app 20

  def validate_url(changeset) do
    changeset
    |> validate_required([:url])
    |> validate_change(:url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
          # Don't allow localhost in production
          if Mix.env() == :prod && host in ["localhost", "127.0.0.1"] do
            [url: "cannot use localhost in production"]
          else
            []
          end
        _ ->
          [url: "must be a valid HTTPS URL"]
      end
    end)
  end

  def validate_events(changeset) do
    changeset
    |> validate_required([:events])
    |> validate_change(:events, fn :events, events ->
      cond do
        !is_list(events) ->
          [events: "must be a list"]
        events == [] ->
          [events: "must have at least one event"]
        invalid = events -- @valid_events; invalid != [] ->
          [events: "contains invalid events: #{Enum.join(invalid, ", ")}"]
        true ->
          []
      end
    end)
  end

  def validate_status(changeset) do
    validate_inclusion(changeset, :status, @statuses)
  end

  def validate_webhook_limit(application_id) do
    count = Conezia.Repo.aggregate(
      from(w in Conezia.Platform.Webhook, where: w.application_id == ^application_id),
      :count
    )

    if count >= @max_webhooks_per_app do
      {:error, "maximum of #{@max_webhooks_per_app} webhooks per application"}
    else
      :ok
    end
  end

  def valid_events, do: @valid_events
end
```

---

## 12. Cross-Field & Business Rule Validation

### 12.1 Cross-Field Validation Examples

```elixir
defmodule Conezia.Validators.CrossField do
  import Ecto.Changeset

  @doc """
  Validates that if recurrence is set, the due_at must be reasonable
  for the frequency.
  """
  def validate_recurrence_and_due_at(changeset) do
    recurrence = get_field(changeset, :recurrence_rule)
    due_at = get_field(changeset, :due_at)

    if recurrence && due_at do
      freq = Map.get(recurrence, "freq")
      interval = Map.get(recurrence, "interval", 1)

      min_interval = case freq do
        "daily" -> 1
        "weekly" -> 7
        "monthly" -> 28
        "yearly" -> 365
        _ -> 1
      end * interval

      # Warn if due date is very far in the past for recurring
      days_ago = DateTime.diff(DateTime.utc_now(), due_at, :day)

      if days_ago > min_interval * 10 do
        add_error(changeset, :due_at,
          "recurring reminder due date is very far in the past")
      else
        changeset
      end
    else
      changeset
    end
  end

  @doc """
  Validates that entity type and relationship type are compatible.
  """
  def validate_entity_relationship_compatibility(changeset) do
    entity_type = get_field(changeset, :entity_type)
    relationship_type = get_field(changeset, :relationship_type)

    incompatible = %{
      "thing" => ["friend", "family", "colleague"],
      "service" => ["friend", "family"],
      "abstract" => ["friend", "family", "colleague", "client"]
    }

    invalid_types = Map.get(incompatible, entity_type, [])

    if relationship_type in invalid_types do
      add_error(changeset, :relationship_type,
        "#{relationship_type} is not valid for #{entity_type} entities")
    else
      changeset
    end
  end

  @doc """
  Validates smart group rules reference valid tags.
  """
  def validate_smart_group_tag_references(changeset, user_id) do
    rules = get_field(changeset, :rules)
    tag_names = get_in(rules, ["tags"]) || []

    if tag_names != [] do
      existing_tags = Conezia.Repo.all(
        from t in Conezia.Entities.Tag,
        where: t.user_id == ^user_id and t.name in ^tag_names,
        select: t.name
      )

      missing = tag_names -- existing_tags

      if missing != [] do
        add_error(changeset, :rules,
          "references non-existent tags: #{Enum.join(missing, ", ")}")
      else
        changeset
      end
    else
      changeset
    end
  end
end
```

---

## 13. Validation Error Format

### 13.1 Standard Error Response

```elixir
defmodule ConeziaWeb.ErrorHelpers do
  def format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> flatten_errors()
  end

  defp flatten_errors(errors, prefix \\ []) do
    Enum.flat_map(errors, fn
      {key, %{} = nested} ->
        flatten_errors(nested, prefix ++ [key])
      {key, messages} when is_list(messages) ->
        field = (prefix ++ [key]) |> Enum.join(".")
        Enum.map(messages, fn msg ->
          %{
            field: field,
            code: error_code(msg),
            message: msg
          }
        end)
    end)
  end

  defp error_code(message) do
    cond do
      String.contains?(message, "required") -> "required"
      String.contains?(message, "format") -> "invalid_format"
      String.contains?(message, "length") -> "invalid_length"
      String.contains?(message, "must be") -> "invalid_value"
      String.contains?(message, "already") -> "already_exists"
      true -> "invalid"
    end
  end
end
```

### 13.2 Example Error Response

```json
{
  "error": {
    "type": "https://api.conezia.com/errors/validation-error",
    "title": "Validation Error",
    "status": 422,
    "detail": "The request contains invalid data.",
    "errors": [
      {
        "field": "email",
        "code": "invalid_format",
        "message": "must be a valid email address"
      },
      {
        "field": "password",
        "code": "invalid_length",
        "message": "must be at least 8 characters"
      },
      {
        "field": "identifiers.0.value",
        "code": "invalid_format",
        "message": "must be in E.164 format (e.g., +12025551234)"
      }
    ]
  }
}
```

---

*Document Version: 1.0*
*Created: 2026-01-17*
