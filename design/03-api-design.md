# Conezia API Design

## 1. Overview

This document defines the REST API design for Conezia, including endpoint specifications, request/response formats, and error handling.

### 1.1 API Conventions

| Convention | Description |
|------------|-------------|
| **Base URL** | `/api/v1` |
| **Format** | JSON (application/json) |
| **Authentication** | Bearer token (JWT) or API key |
| **Pagination** | Cursor-based with `limit` and `cursor` params |
| **Dates** | ISO 8601 format (UTC) |
| **IDs** | UUID v4 |
| **Errors** | RFC 7807 Problem Details |

### 1.2 Common Headers

**Request Headers:**
```
Authorization: Bearer <token>
Content-Type: application/json
Accept: application/json
X-Request-ID: <uuid>  # Optional, for tracing
```

**Response Headers:**
```
Content-Type: application/json
X-Request-ID: <uuid>
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1640000000
```

---

## 2. Authentication Endpoints

### 2.1 Google OAuth

```
POST /api/v1/auth/google
```

Authenticate via Google OAuth.

**Request:**
```json
{
  "code": "4/P7q7W91a-oMsCeLvIaQm6bTrgtp7",
  "redirect_uri": "https://app.conezia.com/auth/callback"
}
```

**Response (200):**
```json
{
  "data": {
    "user": {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "email": "user@example.com",
      "name": "John Doe",
      "avatar_url": "https://...",
      "timezone": "America/New_York"
    },
    "token": {
      "access_token": "eyJhbGciOiJIUzI1NiIs...",
      "token_type": "Bearer",
      "expires_in": 86400
    }
  }
}
```

### 2.2 Email/Password Login

```
POST /api/v1/auth/login
```

**Request:**
```json
{
  "email": "user@example.com",
  "password": "SecureP@ssw0rd!"
}
```

**Response (200):**
```json
{
  "data": {
    "user": { ... },
    "token": { ... }
  }
}
```

**Response (401):**
```json
{
  "error": {
    "type": "https://api.conezia.com/errors/invalid-credentials",
    "title": "Invalid credentials",
    "status": 401,
    "detail": "The email or password is incorrect."
  }
}
```

### 2.3 Registration

```
POST /api/v1/auth/register
```

**Request:**
```json
{
  "email": "newuser@example.com",
  "password": "SecureP@ssw0rd!",
  "name": "Jane Smith",
  "timezone": "Europe/London"
}
```

**Response (201):**
```json
{
  "data": {
    "user": {
      "id": "...",
      "email": "newuser@example.com",
      "name": "Jane Smith",
      "email_verified": false
    },
    "token": { ... }
  },
  "meta": {
    "message": "Verification email sent"
  }
}
```

### 2.4 Token Refresh

```
POST /api/v1/auth/refresh
```

**Request:**
```json
{
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4..."
}
```

### 2.5 Password Reset

```
POST /api/v1/auth/forgot-password
```

**Request:**
```json
{
  "email": "user@example.com"
}
```

**Response (200):**
```json
{
  "meta": {
    "message": "If an account exists, a reset email has been sent"
  }
}
```

```
POST /api/v1/auth/reset-password
```

**Request:**
```json
{
  "token": "reset-token-from-email",
  "password": "NewSecureP@ssw0rd!"
}
```

### 2.6 Email Verification

```
POST /api/v1/auth/verify-email
```

**Request:**
```json
{
  "token": "verification-token-from-email"
}
```

### 2.7 Logout

```
POST /api/v1/auth/logout
```

Invalidates the current session token.

---

## 3. User Endpoints

### 3.1 Get Current User

```
GET /api/v1/users/me
```

**Response (200):**
```json
{
  "data": {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "email": "user@example.com",
    "name": "John Doe",
    "avatar_url": "https://...",
    "timezone": "America/New_York",
    "email_verified": true,
    "settings": {
      "theme": "light",
      "language": "en"
    },
    "inserted_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-06-20T14:45:00Z"
  }
}
```

### 3.2 Update Current User

```
PUT /api/v1/users/me
```

**Request:**
```json
{
  "name": "John D. Doe",
  "timezone": "America/Los_Angeles",
  "avatar_url": "https://..."
}
```

### 3.3 Delete Account

```
DELETE /api/v1/users/me
```

**Request:**
```json
{
  "password": "current-password",
  "confirmation": "DELETE MY ACCOUNT"
}
```

### 3.4 User Preferences

```
GET /api/v1/users/me/preferences
PUT /api/v1/users/me/preferences
```

**Response/Request:**
```json
{
  "data": {
    "theme": "dark",
    "language": "en",
    "date_format": "YYYY-MM-DD",
    "time_format": "24h",
    "default_reminder_time": "09:00",
    "digest_frequency": "weekly",
    "digest_day": "monday"
  }
}
```

### 3.5 Notification Settings

```
GET /api/v1/users/me/notifications
PUT /api/v1/users/me/notifications
```

**Response/Request:**
```json
{
  "data": {
    "email": {
      "reminders": true,
      "digest": true,
      "health_alerts": true,
      "security": true
    },
    "push": {
      "reminders": true,
      "messages": true,
      "health_alerts": false
    },
    "in_app": {
      "all": true
    },
    "quiet_hours": {
      "enabled": true,
      "start": "22:00",
      "end": "08:00",
      "timezone": "America/New_York"
    }
  }
}
```

---

## 4. Entity Endpoints

### 4.1 List Entities

```
GET /api/v1/entities
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `type` | string | Filter by entity type |
| `tag` | string | Filter by tag name |
| `tags[]` | array | Filter by multiple tags (OR) |
| `status` | string | `active`, `archived`, or `all` |
| `q` | string | Search query |
| `sort` | string | `name`, `last_interaction`, `created` |
| `order` | string | `asc` or `desc` |
| `limit` | integer | Max results (default: 50, max: 100) |
| `cursor` | string | Pagination cursor |

**Response (200):**
```json
{
  "data": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "type": "person",
      "name": "Alice Johnson",
      "description": "College friend from Stanford",
      "avatar_url": "https://...",
      "last_interaction_at": "2024-06-15T14:30:00Z",
      "relationship": {
        "id": "...",
        "type": "friend",
        "strength": "close",
        "status": "active",
        "health_score": "good"
      },
      "tags": [
        {"id": "...", "name": "Friends", "color": "blue"},
        {"id": "...", "name": "Stanford", "color": "red"}
      ],
      "primary_identifiers": {
        "email": "alice@example.com",
        "phone": "+14155551234"
      },
      "inserted_at": "2024-01-10T08:00:00Z",
      "updated_at": "2024-06-15T14:30:00Z"
    }
  ],
  "meta": {
    "total": 152,
    "has_more": true,
    "next_cursor": "eyJpZCI6Ij..."
  }
}
```

### 4.2 Get Entity

```
GET /api/v1/entities/:id
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `include` | string | Comma-separated: `identifiers,tags,groups,recent_interactions` |

**Response (200):**
```json
{
  "data": {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "type": "person",
    "name": "Alice Johnson",
    "description": "College friend from Stanford. Works at Google as a PM.",
    "avatar_url": "https://...",
    "metadata": {
      "birthday": "1990-03-15",
      "company": "Google",
      "title": "Product Manager"
    },
    "last_interaction_at": "2024-06-15T14:30:00Z",
    "archived_at": null,
    "relationship": {
      "id": "...",
      "type": "friend",
      "strength": "close",
      "status": "active",
      "started_at": "2015-09-01",
      "health_threshold_days": 30,
      "notes": "Met in CS101 class"
    },
    "identifiers": [
      {"id": "...", "type": "email", "value": "alice@example.com", "label": "Personal", "is_primary": true},
      {"id": "...", "type": "email", "value": "alice@google.com", "label": "Work", "is_primary": false},
      {"id": "...", "type": "phone", "value": "+14155551234", "label": "Mobile", "is_primary": true},
      {"id": "...", "type": "social_handle", "value": "@alicejohnson", "label": "Twitter", "is_primary": false}
    ],
    "tags": [
      {"id": "...", "name": "Friends", "color": "blue"},
      {"id": "...", "name": "Stanford", "color": "red"}
    ],
    "groups": [
      {"id": "...", "name": "Close Friends"},
      {"id": "...", "name": "Tech Industry"}
    ],
    "recent_interactions": [
      {"id": "...", "type": "meeting", "title": "Caught up over coffee", "occurred_at": "2024-06-15T14:30:00Z"}
    ],
    "inserted_at": "2024-01-10T08:00:00Z",
    "updated_at": "2024-06-15T14:30:00Z"
  }
}
```

### 4.3 Create Entity

```
POST /api/v1/entities
```

**Request:**
```json
{
  "type": "person",
  "name": "Bob Smith",
  "description": "Met at tech conference",
  "metadata": {
    "company": "Startup Inc",
    "title": "CTO"
  },
  "relationship": {
    "type": "colleague",
    "strength": "acquaintance"
  },
  "identifiers": [
    {"type": "email", "value": "bob@startup.com", "label": "Work", "is_primary": true},
    {"type": "phone", "value": "+14155559876", "label": "Mobile"}
  ],
  "tag_ids": ["tag-uuid-1", "tag-uuid-2"]
}
```

**Response (201):**
```json
{
  "data": {
    "id": "new-entity-uuid",
    ...
  },
  "meta": {
    "potential_duplicates": [
      {
        "id": "existing-entity-uuid",
        "name": "Robert Smith",
        "match_reason": "Similar email domain",
        "confidence": 0.65
      }
    ]
  }
}
```

### 4.4 Update Entity

```
PUT /api/v1/entities/:id
```

**Request:**
```json
{
  "name": "Robert (Bob) Smith",
  "description": "Updated description",
  "metadata": {
    "company": "New Startup Inc",
    "title": "CEO"
  }
}
```

### 4.5 Delete Entity

```
DELETE /api/v1/entities/:id
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `permanent` | boolean | If true, permanently delete. Otherwise archive. |

### 4.6 Merge Entities

```
POST /api/v1/entities/merge
```

Merges two entities into one. The source entity is merged into the target entity, and the source entity is deleted after a successful merge.

**Request:**
```json
{
  "source_id": "entity-to-merge-from",
  "target_id": "entity-to-merge-into",
  "options": {
    "keep_source_name": false,
    "merge_identifiers": true,
    "merge_tags": true,
    "merge_interactions": true,
    "merge_metadata": true
  }
}
```

**Response (200):**
```json
{
  "data": {
    "id": "entity-to-merge-into",
    "type": "person",
    "name": "Alice Johnson",
    "description": "Merged description from both entities",
    "merged_at": "2024-06-20T10:30:00Z",
    "merge_summary": {
      "source_entity_id": "entity-to-merge-from",
      "identifiers_added": 3,
      "tags_added": 2,
      "interactions_transferred": 15,
      "metadata_fields_merged": ["company", "title"]
    }
  },
  "meta": {
    "message": "Entities merged successfully"
  }
}
```

**Error Responses:**

**404 - Entity Not Found:**
```json
{
  "error": {
    "type": "https://api.conezia.com/errors/not-found",
    "title": "Not Found",
    "status": 404,
    "detail": "Source entity with ID 'entity-uuid' not found.",
    "instance": "/api/v1/entities/merge"
  }
}
```

**409 - Conflict (Same Entity):**
```json
{
  "error": {
    "type": "https://api.conezia.com/errors/conflict",
    "title": "Conflict",
    "status": 409,
    "detail": "Cannot merge an entity with itself.",
    "instance": "/api/v1/entities/merge"
  }
}
```

**409 - Conflict (Type Mismatch):**
```json
{
  "error": {
    "type": "https://api.conezia.com/errors/conflict",
    "title": "Conflict",
    "status": 409,
    "detail": "Cannot merge entities of different types (person and organization).",
    "instance": "/api/v1/entities/merge"
  }
}
```

**422 - Validation Error:**
```json
{
  "error": {
    "type": "https://api.conezia.com/errors/validation-error",
    "title": "Validation Error",
    "status": 422,
    "detail": "Invalid merge request.",
    "errors": [
      {
        "field": "source_id",
        "code": "required",
        "message": "is required"
      },
      {
        "field": "target_id",
        "code": "required",
        "message": "is required"
      }
    ]
  }
}
```

### 4.7 Check Duplicates

```
GET /api/v1/entities/duplicates
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | Name to check |
| `email` | string | Email to check |
| `phone` | string | Phone to check |

**Response (200):**
```json
{
  "data": {
    "has_duplicates": true,
    "matches": [
      {
        "id": "...",
        "name": "...",
        "type": "...",
        "match_type": "email_exact",
        "confidence": 1.0
      }
    ]
  }
}
```

---

## 5. Relationship Endpoints

### 5.1 List Relationships

```
GET /api/v1/relationships
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `type` | string | Relationship type filter |
| `status` | string | `active`, `inactive`, `archived` |
| `health` | string | `good`, `warning`, `critical` |

### 5.2 Create Relationship

```
POST /api/v1/relationships
```

**Request:**
```json
{
  "entity_id": "entity-uuid",
  "type": "friend",
  "strength": "regular",
  "started_at": "2020-01-15",
  "health_threshold_days": 14,
  "notes": "Met through mutual friends"
}
```

### 5.3 Update Relationship

```
PUT /api/v1/relationships/:id
```

### 5.4 Delete Relationship

```
DELETE /api/v1/relationships/:id
```

---

## 6. Communication Endpoints

### 6.1 List Conversations

```
GET /api/v1/conversations
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `entity_id` | uuid | Filter by entity |
| `channel` | string | Filter by channel |
| `archived` | boolean | Include archived |

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "entity": {
        "id": "...",
        "name": "Alice Johnson",
        "avatar_url": "..."
      },
      "channel": "email",
      "subject": "Re: Project Update",
      "last_message_at": "2024-06-20T10:30:00Z",
      "last_message_preview": "Thanks for the update! I'll review...",
      "unread_count": 2,
      "is_archived": false
    }
  ]
}
```

### 6.2 Get Conversation

```
GET /api/v1/conversations/:id
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `limit` | integer | Messages per page |
| `before` | string | Cursor for older messages |

**Response (200):**
```json
{
  "data": {
    "id": "...",
    "entity": { ... },
    "channel": "email",
    "subject": "Re: Project Update",
    "messages": [
      {
        "id": "...",
        "direction": "inbound",
        "content": "Thanks for the update!",
        "sent_at": "2024-06-20T10:30:00Z",
        "read_at": "2024-06-20T10:35:00Z",
        "attachments": []
      },
      {
        "id": "...",
        "direction": "outbound",
        "content": "Here's the project update...",
        "sent_at": "2024-06-20T09:00:00Z",
        "read_at": null,
        "attachments": [
          {"id": "...", "filename": "report.pdf", "mime_type": "application/pdf", "size_bytes": 102400}
        ]
      }
    ]
  },
  "meta": {
    "has_more": true,
    "before_cursor": "..."
  }
}
```

### 6.3 Send Message

```
POST /api/v1/communications
```

**Request:**
```json
{
  "entity_id": "entity-uuid",
  "channel": "internal",
  "content": "Hey, wanted to follow up on our conversation!",
  "conversation_id": "optional-existing-conversation"
}
```

### 6.4 Update Conversation

```
PUT /api/v1/conversations/:id
```

**Request:**
```json
{
  "subject": "Updated subject line",
  "is_archived": true
}
```

### 6.5 Delete Conversation

```
DELETE /api/v1/conversations/:id
```

Deletes a conversation and all its messages.

### 6.6 Entity Conversations

```
GET /api/v1/entities/:id/conversations
```

---

## 7. Reminder Endpoints

### 7.1 List Reminders

```
GET /api/v1/reminders
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | `pending`, `completed`, `overdue`, `snoozed` |
| `entity_id` | uuid | Filter by entity |
| `type` | string | Reminder type |
| `due_before` | datetime | Due before date |
| `due_after` | datetime | Due after date |

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "type": "follow_up",
      "title": "Follow up with Alice",
      "description": "Discuss project collaboration",
      "due_at": "2024-06-25T09:00:00Z",
      "entity": {
        "id": "...",
        "name": "Alice Johnson",
        "avatar_url": "..."
      },
      "recurrence_rule": null,
      "notification_channels": ["in_app", "email"],
      "status": "pending",
      "snoozed_until": null,
      "completed_at": null
    }
  ]
}
```

### 7.2 Create Reminder

```
POST /api/v1/reminders
```

**Request:**
```json
{
  "type": "follow_up",
  "title": "Check in with Bob",
  "description": "See how the new role is going",
  "due_at": "2024-07-01T10:00:00Z",
  "entity_id": "entity-uuid",
  "notification_channels": ["in_app", "push"],
  "recurrence_rule": {
    "freq": "monthly",
    "interval": 1,
    "count": 6
  }
}
```

### 7.3 Update Reminder

```
PUT /api/v1/reminders/:id
```

**Request:**
```json
{
  "title": "Updated reminder title",
  "description": "Updated description",
  "due_at": "2024-07-05T10:00:00Z",
  "notification_channels": ["in_app", "email", "push"],
  "recurrence_rule": {
    "freq": "weekly",
    "interval": 2
  }
}
```

### 7.4 Delete Reminder

```
DELETE /api/v1/reminders/:id
```

### 7.5 Snooze Reminder

```
POST /api/v1/reminders/:id/snooze
```

**Request:**
```json
{
  "until": "2024-06-26T09:00:00Z"
}
```

Or use preset durations:
```json
{
  "duration": "1_hour"  // 1_hour, 3_hours, tomorrow, next_week
}
```

### 7.6 Complete Reminder

```
POST /api/v1/reminders/:id/complete
```

### 7.7 Entity Reminders

```
GET /api/v1/entities/:id/reminders
```

---

## 8. Tag Endpoints

### 8.1 List Tags

```
GET /api/v1/tags
```

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "name": "Friends",
      "color": "blue",
      "description": "Personal friends",
      "entity_count": 45
    }
  ]
}
```

### 8.2 Create Tag

```
POST /api/v1/tags
```

**Request:**
```json
{
  "name": "Investors",
  "color": "green",
  "description": "Potential and current investors"
}
```

### 8.3 Update Tag

```
PUT /api/v1/tags/:id
```

### 8.4 Delete Tag

```
DELETE /api/v1/tags/:id
```

### 8.5 Tag Entities

```
POST /api/v1/entities/:id/tags
```

**Request:**
```json
{
  "tag_ids": ["tag-uuid-1", "tag-uuid-2"]
}
```

```
DELETE /api/v1/entities/:id/tags/:tag_id
```

---

## 9. Group Endpoints

### 9.1 List Groups

```
GET /api/v1/groups
```

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "name": "Holiday Card List",
      "description": "People to send holiday cards to",
      "is_smart": false,
      "entity_count": 32
    },
    {
      "id": "...",
      "name": "Needs Attention",
      "description": "Auto-populated: relationships needing attention",
      "is_smart": true,
      "rules": {
        "relationship_status": "active",
        "last_interaction_days": 30
      },
      "entity_count": 8
    }
  ]
}
```

### 9.2 Create Group

```
POST /api/v1/groups
```

**Static Group:**
```json
{
  "name": "Investors",
  "description": "Current and potential investors",
  "entity_ids": ["entity-1", "entity-2"]
}
```

**Smart Group:**
```json
{
  "name": "Tech Contacts",
  "description": "All tech industry contacts",
  "is_smart": true,
  "rules": {
    "tags": ["Tech"],
    "type": "person"
  }
}
```

### 9.3 Get Group

```
GET /api/v1/groups/:id
```

**Response (200):**
```json
{
  "data": {
    "id": "...",
    "name": "Holiday Card List",
    "description": "People to send holiday cards to",
    "is_smart": false,
    "entity_count": 32,
    "inserted_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-06-10T14:30:00Z"
  }
}
```

### 9.4 Update Group

```
PUT /api/v1/groups/:id
```

**Request:**
```json
{
  "name": "Holiday Card List 2024",
  "description": "Updated description",
  "rules": {
    "tags": ["Family", "Friends"]
  }
}
```

### 9.5 Delete Group

```
DELETE /api/v1/groups/:id
```

### 9.6 Get Group Members

```
GET /api/v1/groups/:id/entities
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `limit` | integer | Max results (default: 50) |
| `cursor` | string | Pagination cursor |

### 9.7 Add Entities to Group

```
POST /api/v1/groups/:id/entities
```

**Request:**
```json
{
  "entity_ids": ["entity-1", "entity-2"]
}
```

Note: Cannot add entities to smart groups (they auto-populate based on rules).

### 9.8 Remove Entity from Group

```
DELETE /api/v1/groups/:id/entities/:entity_id
```

---

## 10. Search Endpoint

### 10.1 Global Search

```
GET /api/v1/search
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | string | Search query (required) |
| `type` | string | Filter by resource type: `entity`, `interaction`, `communication` |
| `entity_type` | string | Filter by entity type |
| `tags` | array | Filter by tags |
| `date_from` | date | Results after date |
| `date_to` | date | Results before date |
| `limit` | integer | Max results per type |

**Response (200):**
```json
{
  "data": {
    "entities": [
      {
        "id": "...",
        "name": "Alice Johnson",
        "type": "person",
        "match_context": "...alice@example.com...",
        "score": 0.95
      }
    ],
    "interactions": [
      {
        "id": "...",
        "type": "meeting",
        "title": "Meeting with Alice",
        "entity": {"id": "...", "name": "Alice Johnson"},
        "match_context": "...discussed Alice's new project...",
        "occurred_at": "2024-06-15T14:00:00Z",
        "score": 0.82
      }
    ],
    "communications": [
      {
        "id": "...",
        "channel": "email",
        "entity": {"id": "...", "name": "Alice Johnson"},
        "match_context": "...Hi Alice, following up on...",
        "sent_at": "2024-06-10T09:00:00Z",
        "score": 0.78
      }
    ]
  },
  "meta": {
    "query": "alice project",
    "total_results": 15,
    "search_time_ms": 45
  }
}
```

---

## 11. Interaction Endpoints

### 11.1 List Interactions

```
GET /api/v1/interactions
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `entity_id` | uuid | Filter by entity |
| `type` | string | Filter by interaction type |
| `since` | datetime | Interactions after date |
| `until` | datetime | Interactions before date |
| `limit` | integer | Max results (default: 50) |
| `cursor` | string | Pagination cursor |

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "type": "meeting",
      "title": "Coffee catch-up",
      "content": "Discussed new job opportunity...",
      "occurred_at": "2024-06-15T14:00:00Z",
      "entity": {
        "id": "...",
        "name": "Alice Johnson",
        "avatar_url": "..."
      },
      "attachments": [],
      "inserted_at": "2024-06-15T15:00:00Z"
    }
  ],
  "meta": {
    "has_more": true,
    "next_cursor": "..."
  }
}
```

### 11.2 Get Interaction

```
GET /api/v1/interactions/:id
```

### 11.3 Create Interaction

```
POST /api/v1/interactions
```

**Request:**
```json
{
  "entity_id": "entity-uuid",
  "type": "call",
  "title": "Quick check-in call",
  "content": "Called to see how the new project is going. They mentioned...",
  "occurred_at": "2024-06-20T10:30:00Z"
}
```

Valid interaction types: `email`, `call`, `meeting`, `message`

**Response (201):**
```json
{
  "data": {
    "id": "new-interaction-uuid",
    "type": "call",
    "title": "Quick check-in call",
    "content": "...",
    "occurred_at": "2024-06-20T10:30:00Z",
    "entity": { ... },
    "inserted_at": "2024-06-20T10:35:00Z"
  }
}
```

### 11.4 Update Interaction

```
PUT /api/v1/interactions/:id
```

### 11.5 Delete Interaction

```
DELETE /api/v1/interactions/:id
```

### 11.6 Entity Interactions

```
GET /api/v1/entities/:id/interactions
```

Returns interactions for a specific entity.

### 11.7 Entity History (Timeline)

```
GET /api/v1/entities/:id/history
```

Returns a combined timeline of interactions, communications, and relationship changes.

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `types` | array | Filter by event types: `interaction`, `communication`, `reminder`, `relationship_change` |
| `limit` | integer | Max results (default: 50) |
| `cursor` | string | Pagination cursor |

**Response (200):**
```json
{
  "data": [
    {
      "event_type": "interaction",
      "event_id": "...",
      "title": "Coffee catch-up",
      "summary": "Meeting at downtown cafe",
      "occurred_at": "2024-06-15T14:00:00Z"
    },
    {
      "event_type": "communication",
      "event_id": "...",
      "title": "Email: Project Update",
      "summary": "Thanks for the update! I'll review...",
      "occurred_at": "2024-06-10T09:00:00Z"
    }
  ],
  "meta": {
    "has_more": true,
    "next_cursor": "..."
  }
}
```

---

## 12. Identifier Endpoints

### 12.1 List Identifiers

```
GET /api/v1/identifiers
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `entity_id` | uuid | Filter by entity |
| `type` | string | Filter by identifier type |

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "entity_id": "...",
      "type": "email",
      "value": "alice@example.com",
      "label": "Personal",
      "is_primary": true,
      "verified_at": "2024-01-15T10:00:00Z"
    }
  ]
}
```

### 12.2 Create Identifier

```
POST /api/v1/identifiers
```

**Request:**
```json
{
  "entity_id": "entity-uuid",
  "type": "phone",
  "value": "+14155551234",
  "label": "Mobile",
  "is_primary": true
}
```

### 12.3 Update Identifier

```
PUT /api/v1/identifiers/:id
```

### 12.4 Delete Identifier

```
DELETE /api/v1/identifiers/:id
```

### 12.5 Check Identifier (Duplicate Detection)

```
GET /api/v1/identifiers/check
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `type` | string | Identifier type (required) |
| `value` | string | Value to check (required) |

**Response (200):**
```json
{
  "data": {
    "exists": true,
    "matches": [
      {
        "entity_id": "...",
        "entity_name": "Alice Johnson",
        "identifier_id": "...",
        "is_primary": true
      }
    ]
  }
}
```

### 12.6 Entity Identifiers

```
GET /api/v1/entities/:id/identifiers
POST /api/v1/entities/:id/identifiers
```

---

## 13. External Account Endpoints

### 13.1 List External Accounts

```
GET /api/v1/external-accounts
```

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "service_name": "google_contacts",
      "account_identifier": "user@gmail.com",
      "status": "connected",
      "scopes": ["contacts.readonly"],
      "last_synced_at": "2024-06-20T08:00:00Z",
      "inserted_at": "2024-01-15T10:00:00Z"
    },
    {
      "id": "...",
      "service_name": "google_calendar",
      "account_identifier": "user@gmail.com",
      "status": "pending_reauth",
      "scopes": ["calendar.readonly"],
      "last_synced_at": "2024-06-15T08:00:00Z",
      "sync_error": "Token expired, please re-authenticate"
    }
  ]
}
```

### 13.2 Connect External Account

```
POST /api/v1/external-accounts
```

**Request:**
```json
{
  "service_name": "google_contacts",
  "oauth_code": "4/P7q7W91a-oMsCeLvIaQm6bTrgtp7",
  "redirect_uri": "https://app.conezia.com/connect/callback"
}
```

**Response (201):**
```json
{
  "data": {
    "id": "...",
    "service_name": "google_contacts",
    "account_identifier": "user@gmail.com",
    "status": "connected",
    "scopes": ["contacts.readonly"]
  }
}
```

### 13.3 Get External Account

```
GET /api/v1/external-accounts/:id
```

### 13.4 Disconnect External Account

```
DELETE /api/v1/external-accounts/:id
```

### 13.5 Sync External Account

```
POST /api/v1/external-accounts/:id/sync
```

Triggers a manual sync of the external account.

**Response (202):**
```json
{
  "data": {
    "sync_job_id": "...",
    "status": "queued"
  }
}
```

### 13.6 Re-authorize External Account

```
POST /api/v1/external-accounts/:id/reauth
```

Returns a new OAuth URL to re-authenticate when token has expired.

**Response (200):**
```json
{
  "data": {
    "auth_url": "https://accounts.google.com/o/oauth2/v2/auth?..."
  }
}
```

---

## 14. Attachment Endpoints

### 14.1 Upload Attachment

```
POST /api/v1/attachments
Content-Type: multipart/form-data
```

**Form Fields:**
- `file`: The file to upload (required)
- `entity_id`: Associate with entity (optional)
- `interaction_id`: Associate with interaction (optional)
- `communication_id`: Associate with communication (optional)

**Response (201):**
```json
{
  "data": {
    "id": "...",
    "filename": "meeting-notes.pdf",
    "mime_type": "application/pdf",
    "size_bytes": 102400,
    "download_url": "https://...",
    "inserted_at": "2024-06-20T10:30:00Z"
  }
}
```

### 14.2 Get Attachment Metadata

```
GET /api/v1/attachments/:id
```

### 14.3 Download Attachment

```
GET /api/v1/attachments/:id/download
```

Returns a redirect to a signed download URL.

### 14.4 Delete Attachment

```
DELETE /api/v1/attachments/:id
```

### 14.5 Entity Attachments

```
GET /api/v1/entities/:id/attachments
```

---

## 15. Onboarding Endpoints

### 15.1 Get Onboarding Status

```
GET /api/v1/users/me/onboarding
```

**Response (200):**
```json
{
  "data": {
    "completed": false,
    "current_step": 3,
    "steps": [
      {"step": 1, "name": "welcome", "completed": true},
      {"step": 2, "name": "profile_setup", "completed": true},
      {"step": 3, "name": "import_contacts", "completed": false, "skipped": false},
      {"step": 4, "name": "create_first_entity", "completed": false},
      {"step": 5, "name": "set_first_reminder", "completed": false},
      {"step": 6, "name": "tour_dashboard", "completed": false}
    ],
    "started_at": "2024-06-20T10:00:00Z"
  }
}
```

### 15.2 Update Onboarding Progress

```
PUT /api/v1/users/me/onboarding
```

**Request:**
```json
{
  "step": "import_contacts",
  "action": "complete"  // or "skip"
}
```

### 15.3 Complete Onboarding

```
POST /api/v1/users/me/onboarding/complete
```

Marks the entire onboarding flow as complete.

---

## 16. Import/Export Endpoints

### 16.1 Start Import

```
POST /api/v1/import
```

**File Upload:**
```
POST /api/v1/import
Content-Type: multipart/form-data

file: <csv or vcard file>
source: csv
```

**OAuth Source:**
```json
{
  "source": "google",
  "oauth_token": "google-oauth-token"
}
```

**Response (202):**
```json
{
  "data": {
    "job_id": "import-job-uuid",
    "status": "pending",
    "source": "csv"
  }
}
```

### 16.2 Get Import Status

```
GET /api/v1/import/:job_id
```

**Response (200):**
```json
{
  "data": {
    "id": "...",
    "status": "processing",
    "source": "csv",
    "progress": {
      "total_records": 150,
      "processed_records": 75,
      "created_records": 60,
      "merged_records": 10,
      "skipped_records": 5
    },
    "started_at": "2024-06-20T10:00:00Z",
    "estimated_completion": "2024-06-20T10:05:00Z"
  }
}
```

### 16.3 Import Preview/Confirm

```
POST /api/v1/import/:job_id/confirm
```

**Request:**
```json
{
  "merge_strategy": "skip_duplicates",  // skip_duplicates, merge, create_all
  "field_mapping": {
    "First Name": "name",
    "Email Address": "email",
    "Phone": "phone"
  }
}
```

### 16.4 Cancel Import

```
DELETE /api/v1/import/:job_id
```

### 16.5 Export Data

```
GET /api/v1/export
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `format` | string | `csv`, `vcard`, `json` |
| `entity_ids` | array | Specific entities (optional) |
| `include` | string | `identifiers`, `interactions`, `all` |

**Response (200):**
Returns file download or:
```json
{
  "data": {
    "download_url": "https://...",
    "expires_at": "2024-06-20T11:00:00Z"
  }
}
```

---

## 17. Relationship Health Endpoints

### 17.1 Health Summary

```
GET /api/v1/health/summary
```

**Response (200):**
```json
{
  "data": {
    "total_entities": 152,
    "health_breakdown": {
      "good": 120,
      "warning": 25,
      "critical": 7
    },
    "needs_attention": [
      {
        "entity": {"id": "...", "name": "Bob Smith", "avatar_url": "..."},
        "last_interaction_at": "2024-05-01T10:00:00Z",
        "days_since_interaction": 50,
        "threshold_days": 30,
        "suggested_action": "Send a quick check-in message"
      }
    ]
  }
}
```

### 17.2 Weekly Digest

```
GET /api/v1/health/digest
```

**Response (200):**
```json
{
  "data": {
    "period": {
      "start": "2024-06-10",
      "end": "2024-06-17"
    },
    "summary": {
      "interactions_count": 23,
      "new_entities": 3,
      "reminders_completed": 8,
      "relationships_improved": 5,
      "relationships_declining": 2
    },
    "highlights": [
      {
        "type": "birthday_upcoming",
        "entity": {"id": "...", "name": "Alice Johnson"},
        "date": "2024-06-25"
      },
      {
        "type": "milestone",
        "entity": {"id": "...", "name": "Bob Smith"},
        "message": "1 year since you connected"
      }
    ],
    "needs_attention": [ ... ]
  }
}
```

### 17.3 Set Health Threshold

```
PUT /api/v1/entities/:id/health-threshold
```

**Request:**
```json
{
  "threshold_days": 14
}
```

---

## 18. Activity Log Endpoint

### 18.1 List Activity

```
GET /api/v1/activity
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `resource_type` | string | Filter by type |
| `action` | string | Filter by action |
| `since` | datetime | Activity after date |

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "action": "create",
      "resource_type": "entity",
      "resource_id": "...",
      "resource_name": "Alice Johnson",
      "metadata": {},
      "inserted_at": "2024-06-20T10:30:00Z"
    }
  ]
}
```

### 18.2 Entity Activity

```
GET /api/v1/entities/:id/activity
```

---

## 19. Platform API Endpoints

### 19.1 Application Management

```
GET    /api/v1/apps
POST   /api/v1/apps
GET    /api/v1/apps/:id
PUT    /api/v1/apps/:id
DELETE /api/v1/apps/:id
```

**Create Application:**
```json
{
  "name": "My CRM Integration",
  "description": "Syncs contacts with Conezia",
  "website_url": "https://mycrm.com",
  "callback_urls": ["https://mycrm.com/auth/callback"],
  "scopes": ["read:entities", "write:entities"]
}
```

**Response (201):**
```json
{
  "data": {
    "id": "...",
    "name": "My CRM Integration",
    "api_key": "ck_abc123...",  // Only shown once!
    "api_secret": "cs_xyz789...",  // Only shown once!
    "status": "pending"
  },
  "meta": {
    "warning": "Save your API credentials now. They will not be shown again."
  }
}
```

### 19.2 Rotate Credentials

```
POST /api/v1/apps/:id/rotate-secret
```

### 19.3 Webhook Management

```
GET    /api/v1/apps/:app_id/webhooks
POST   /api/v1/apps/:app_id/webhooks
GET    /api/v1/apps/:app_id/webhooks/:id
PUT    /api/v1/apps/:app_id/webhooks/:id
DELETE /api/v1/apps/:app_id/webhooks/:id
```

**Create Webhook:**
```json
{
  "url": "https://mycrm.com/webhooks/conezia",
  "events": ["entity.created", "entity.updated"]
}
```

**Response (201):**
```json
{
  "data": {
    "id": "...",
    "url": "https://mycrm.com/webhooks/conezia",
    "events": ["entity.created", "entity.updated"],
    "secret": "whsec_...",  // For signature verification
    "status": "active"
  }
}
```

### 19.4 Test Webhook

```
POST /api/v1/apps/:app_id/webhooks/:id/test
```

### 19.5 Webhook Deliveries

```
GET /api/v1/apps/:app_id/webhooks/:id/deliveries
```

### 19.6 List Authorized Apps (User Perspective)

```
GET /api/v1/users/me/authorized-apps
```

Lists all third-party applications the current user has authorized.

**Response (200):**
```json
{
  "data": [
    {
      "id": "...",
      "application": {
        "id": "...",
        "name": "My CRM Integration",
        "logo_url": "https://...",
        "website_url": "https://mycrm.com"
      },
      "granted_scopes": ["read:entities", "write:entities"],
      "authorized_at": "2024-06-15T10:00:00Z",
      "last_accessed_at": "2024-06-20T14:30:00Z"
    }
  ]
}
```

### 19.7 Revoke App Authorization

```
DELETE /api/v1/users/me/authorized-apps/:app_id
```

Revokes a third-party application's access to the user's data.

**Response (200):**
```json
{
  "meta": {
    "message": "Application access revoked successfully"
  }
}
```

### 19.8 Get App Authorization Details

```
GET /api/v1/users/me/authorized-apps/:app_id
```

**Response (200):**
```json
{
  "data": {
    "id": "...",
    "application": {
      "id": "...",
      "name": "My CRM Integration",
      "description": "Syncs contacts with Conezia",
      "logo_url": "https://...",
      "website_url": "https://mycrm.com"
    },
    "granted_scopes": ["read:entities", "write:entities"],
    "authorized_at": "2024-06-15T10:00:00Z",
    "last_accessed_at": "2024-06-20T14:30:00Z",
    "access_log": [
      {
        "action": "read:entities",
        "resource_count": 25,
        "timestamp": "2024-06-20T14:30:00Z"
      }
    ]
  }
}
```

### 19.9 Update App Scopes

```
PUT /api/v1/users/me/authorized-apps/:app_id
```

Allows users to modify the scopes granted to an application.

**Request:**
```json
{
  "granted_scopes": ["read:entities"]
}
```

**Response (200):**
```json
{
  "data": {
    "id": "...",
    "granted_scopes": ["read:entities"],
    "updated_at": "2024-06-20T15:00:00Z"
  }
}
```

---

## 20. Error Handling

### 20.1 Error Response Format

All errors follow RFC 7807 Problem Details:

```json
{
  "error": {
    "type": "https://api.conezia.com/errors/validation-error",
    "title": "Validation Error",
    "status": 422,
    "detail": "The request body contains invalid data.",
    "instance": "/api/v1/entities",
    "errors": [
      {
        "field": "email",
        "code": "invalid_format",
        "message": "must be a valid email address"
      },
      {
        "field": "name",
        "code": "required",
        "message": "is required"
      }
    ]
  }
}
```

### 20.2 Error Types

| Status | Type | Title |
|--------|------|-------|
| 400 | bad-request | Bad Request |
| 401 | unauthorized | Unauthorized |
| 403 | forbidden | Forbidden |
| 404 | not-found | Not Found |
| 409 | conflict | Conflict |
| 422 | validation-error | Validation Error |
| 429 | rate-limited | Rate Limit Exceeded |
| 500 | internal-error | Internal Server Error |
| 503 | service-unavailable | Service Unavailable |

### 20.3 Rate Limiting

**Response (429):**
```json
{
  "error": {
    "type": "https://api.conezia.com/errors/rate-limited",
    "title": "Rate Limit Exceeded",
    "status": 429,
    "detail": "You have exceeded the rate limit of 1000 requests per hour.",
    "retry_after": 3600
  }
}
```

---

## 21. Webhook Payloads

### 21.1 Event Structure

```json
{
  "id": "evt_123...",
  "type": "entity.created",
  "created_at": "2024-06-20T10:30:00Z",
  "data": {
    "entity": {
      "id": "...",
      "type": "person",
      "name": "Alice Johnson"
    }
  }
}
```

### 21.2 Signature Verification

Webhooks include a signature header:
```
X-Conezia-Signature: sha256=abc123...
```

Verify by computing HMAC-SHA256 of the raw request body using the webhook secret.

---

*Document Version: 1.0*
*Created: 2026-01-17*
