# Conezia Requirements Document

## 1. Overview

### 1.1 Product Vision
Conezia is "YourLifeConnected" - a unified platform for managing all relationships and connections in a user's life, whether with people, organizations, services, or things. It serves as both a standalone application and a foundational platform that other applications can build upon.

### 1.2 Core Value Proposition
- Complete, clear view of all relationships and connections in one place
- Unified communication across multiple channels
- Historical record of all interactions
- Platform-as-a-service for third-party applications

---

## 2. System Architecture

### 2.1 Platform Role
Conezia operates in two modes:

1. **Standalone Application**: Direct user access via web interface
2. **Platform Service**: Backend infrastructure for third-party applications

### 2.2 Third-Party Application Integration
- Applications powered by Conezia inherit account management, relationship management, and authentication capabilities
- No additional OAuth authorization required for Conezia-powered apps
- Seamless user experience: users of third-party apps automatically interact with Conezia
- New user registration on any Conezia-powered app creates a Conezia account

### 2.3 Technology Stack (Initial)
- **Platform**: Web-based (primary)
- **Future Extensions**: Mobile apps (iOS, Android), other mediums
- **API**: RESTful API with comprehensive documentation

---

## 3. Functional Requirements

### 3.1 User Account Management

#### 3.1.1 Authentication
| Feature | Priority | Description |
|---------|----------|-------------|
| Google OAuth | P0 (MVP) | Primary authentication method at launch |
| Email/Password | P1 | Traditional authentication with secure password handling |
| Social Network Auth | P2 | Facebook, Apple, LinkedIn, etc. |

#### 3.1.2 Account Features
- User profile management
- Account settings and preferences
- Privacy controls
- Session management
- Account linking (merge multiple auth methods)

### 3.2 Entity Management

#### 3.2.1 Entity Types
Conezia manages relationships with diverse entity types:

| Entity Type | Examples |
|-------------|----------|
| People | Friends, family, colleagues, acquaintances |
| Organizations | Companies, clubs, government agencies |
| Services | Online platforms, subscriptions, utilities |
| Things | Possessions, vehicles, properties |
| Animals | Pets, livestock |
| Abstract | Projects, goals, concepts |

#### 3.2.2 Entity Attributes
Each entity contains:

**Core Attributes**
- Name/Title
- Entity type and subtype
- Description/Notes
- Profile image/icon
- Creation date
- Last modified date

**Relationship Attributes**
- Relationship type (friend, family, service provider, etc.)
- Relationship status (active, inactive, archived)
- Relationship start date
- Custom tags/labels

**Contact Information**
- Multiple phone numbers (with type labels)
- Multiple email addresses (with type labels)
- Physical addresses
- Social media handles
- Websites/URLs

#### 3.2.3 Entity Operations
- Create new entity
- Edit entity details
- Archive/Delete entity
- Merge duplicate entities
- Import entities (contacts, etc.)
- Export entities
- Search and filter entities
- Categorize with tags/groups

### 3.3 Unique Identifier Management

#### 3.3.1 Managed Identifiers
| Identifier Type | Validation | Uniqueness Scope |
|-----------------|------------|------------------|
| Phone Number | Format validation, country code | Global |
| Email Address | Format validation | Global |
| SSN/Tax ID | Format validation, encrypted storage | Per country/region |
| Government IDs | Configurable validation | Per ID type |
| Account Numbers | Custom patterns | Per service |

#### 3.3.2 Identifier Features
- Duplicate detection and warnings
- Identifier verification (optional)
- Privacy levels (who can see)
- Identifier linking across entities
- Historical tracking (old numbers, previous emails)

### 3.4 Communication Management

#### 3.4.1 Communication Channels
| Channel | Type | Implementation |
|---------|------|----------------|
| Internal Chat | Built-in | Real-time messaging within Conezia |
| External Chat | Integration | Connect to WhatsApp, Telegram, etc. |
| Email | Integration | Send/receive via connected accounts |
| Phone | Integration | Click-to-call, call logging |
| SMS | Integration | Send/receive text messages |
| Video | Integration | Connect to Zoom, Meet, etc. |

#### 3.4.2 Communication Features
- Unified inbox across channels
- Conversation threading
- Message search
- Attachments and media
- Read receipts (where supported)
- Communication preferences per entity

### 3.5 Interaction History

#### 3.5.1 Tracked Interactions
- All communications (with content where permitted)
- Notes and observations
- Meetings and events
- Transactions
- Status changes
- File exchanges

#### 3.5.2 History Features
- Chronological timeline view
- Filterable by interaction type
- Searchable content
- Export capabilities
- Privacy controls (what to track)
- Retention policies

### 3.6 User-Entity Account Mapping

#### 3.6.1 Account Registry
- Track user accounts across external services
- Map external accounts to Conezia entities
- Shared entity management (multiple Conezia users referencing same real-world entity)

#### 3.6.2 Mapping Features
- Link external service credentials (securely stored)
- Track account status per service
- Cross-reference entities across users
- Suggest entity merges based on matching identifiers

### 3.7 Reminders and Alerts System

#### 3.7.1 Reminder Types
| Reminder Type | Description |
|---------------|-------------|
| Follow-up Reminders | User-set reminders to contact an entity |
| Recurring Reminders | Repeating reminders (weekly check-in, monthly review) |
| Date-based Alerts | Birthdays, anniversaries, contract renewals |
| Relationship Health Alerts | "You haven't contacted X in 30 days" |
| Event Reminders | Meetings, appointments, scheduled calls |

#### 3.7.2 Reminder Features
- Snooze and reschedule
- Multiple notification channels (in-app, email, push)
- Smart suggestions based on interaction patterns
- Bulk reminder management
- Quiet hours / Do not disturb settings

#### 3.7.3 Relationship Health Scoring
- Automatic tracking of last interaction date per entity
- Configurable "losing touch" thresholds per relationship type
- Visual indicators (green/yellow/red) on entity list
- Weekly digest of relationships needing attention

### 3.8 Contact Import and Export

#### 3.8.1 Import Sources
| Source | Priority | Format |
|--------|----------|--------|
| Google Contacts | P0 (MVP) | OAuth + API |
| CSV/vCard | P0 (MVP) | File upload |
| Apple iCloud | P1 | OAuth + API |
| LinkedIn | P1 | OAuth + API (limited) / CSV export |
| Outlook/Microsoft | P1 | OAuth + API |
| Other CRMs | P2 | CSV/API |

#### 3.8.2 Import Features
- Field mapping wizard
- Duplicate detection during import
- Merge suggestions for similar contacts
- Import preview before committing
- Incremental sync (for OAuth sources)
- Import history and undo

#### 3.8.3 Export Formats
- CSV (universal)
- vCard 4.0 (contacts)
- JSON (full data with relationships)
- PDF (printable contact book)

### 3.9 Smart Features (AI-Powered)

#### 3.9.1 Intelligent Suggestions
- Follow-up recommendations based on interaction patterns
- Best time to contact suggestions
- Relationship strengthening tips
- Meeting prep briefs (summary of recent interactions before scheduled calls)

#### 3.9.2 Auto-Enrichment
- Public data enrichment (company info, social profiles)
- Profile photo suggestions from social media
- Job title / company change detection
- News alerts about entities (optional)

#### 3.9.3 Smart Search
- Natural language search ("people I haven't talked to this month")
- Fuzzy matching for names and identifiers
- Search across all fields including notes and communication content

---

## 4. API Requirements

### 4.1 API Design Principles
- RESTful architecture
- JSON request/response format
- Versioned endpoints (v1, v2, etc.)
- Consistent error handling
- Rate limiting
- Pagination for list endpoints

### 4.2 API Authentication
- API keys for third-party applications
- JWT tokens for user sessions
- Scope-based permissions
- Token refresh mechanism

### 4.3 Core API Endpoints

#### Authentication
```
POST   /api/v1/auth/google        # Google OAuth
POST   /api/v1/auth/login         # Email/password login
POST   /api/v1/auth/register      # New user registration
POST   /api/v1/auth/refresh       # Refresh token
POST   /api/v1/auth/logout        # End session
POST   /api/v1/auth/forgot-password    # Request password reset
POST   /api/v1/auth/reset-password     # Complete password reset
POST   /api/v1/auth/verify-email       # Verify email address
```

#### Users
```
GET    /api/v1/users/me           # Current user profile
PUT    /api/v1/users/me           # Update profile
DELETE /api/v1/users/me           # Delete account
```

#### Entities
```
GET    /api/v1/entities           # List entities (with filters)
POST   /api/v1/entities           # Create entity
GET    /api/v1/entities/:id       # Get entity details
PUT    /api/v1/entities/:id       # Update entity
DELETE /api/v1/entities/:id       # Delete entity
POST   /api/v1/entities/merge     # Merge entities
```

#### Relationships
```
GET    /api/v1/relationships      # List relationships
POST   /api/v1/relationships      # Create relationship
PUT    /api/v1/relationships/:id  # Update relationship
DELETE /api/v1/relationships/:id  # Remove relationship
```

#### Communications
```
GET    /api/v1/communications     # List communications
POST   /api/v1/communications     # Send communication
GET    /api/v1/communications/:id # Get communication details
```

#### Interactions
```
GET    /api/v1/entities/:id/history    # Entity interaction history
POST   /api/v1/entities/:id/notes      # Add note
GET    /api/v1/entities/:id/notes      # List notes
```

#### Identifiers
```
GET    /api/v1/identifiers        # List identifiers
POST   /api/v1/identifiers        # Add identifier
PUT    /api/v1/identifiers/:id    # Update identifier
DELETE /api/v1/identifiers/:id    # Remove identifier
GET    /api/v1/identifiers/check  # Check for duplicates
```

#### Tags
```
GET    /api/v1/tags               # List user's tags
POST   /api/v1/tags               # Create tag
PUT    /api/v1/tags/:id           # Update tag
DELETE /api/v1/tags/:id           # Delete tag
POST   /api/v1/entities/:id/tags  # Add tags to entity
DELETE /api/v1/entities/:id/tags/:tag_id  # Remove tag from entity
```

#### Reminders
```
GET    /api/v1/reminders          # List reminders (with filters: upcoming, overdue, entity)
POST   /api/v1/reminders          # Create reminder
GET    /api/v1/reminders/:id      # Get reminder details
PUT    /api/v1/reminders/:id      # Update reminder
DELETE /api/v1/reminders/:id      # Delete reminder
POST   /api/v1/reminders/:id/snooze    # Snooze reminder
POST   /api/v1/reminders/:id/complete  # Mark reminder complete
GET    /api/v1/entities/:id/reminders  # List reminders for entity
```

#### Search
```
GET    /api/v1/search             # Global search across entities, notes, communications
                                  # Query params: q, type, tags, date_range, limit, offset
```

#### Import/Export
```
POST   /api/v1/import             # Start import job (multipart file or OAuth source)
GET    /api/v1/import/:job_id     # Get import job status
POST   /api/v1/import/:job_id/confirm  # Confirm and apply import
DELETE /api/v1/import/:job_id     # Cancel import job
GET    /api/v1/export             # Export data (query params: format, entities, date_range)
```

#### External Accounts
```
GET    /api/v1/external-accounts  # List connected external accounts
POST   /api/v1/external-accounts  # Connect new external account
GET    /api/v1/external-accounts/:id  # Get account details
PUT    /api/v1/external-accounts/:id  # Update account
DELETE /api/v1/external-accounts/:id  # Disconnect account
POST   /api/v1/external-accounts/:id/sync  # Trigger sync
```

#### Platform: Applications (for developers)
```
GET    /api/v1/apps               # List developer's applications
POST   /api/v1/apps               # Register new application
GET    /api/v1/apps/:id           # Get application details
PUT    /api/v1/apps/:id           # Update application
DELETE /api/v1/apps/:id           # Delete application
POST   /api/v1/apps/:id/rotate-secret  # Rotate API secret
GET    /api/v1/apps/:id/users     # List users who authorized this app
```

#### Platform: Webhooks
```
GET    /api/v1/apps/:app_id/webhooks  # List webhooks for application
POST   /api/v1/apps/:app_id/webhooks  # Create webhook
GET    /api/v1/apps/:app_id/webhooks/:id  # Get webhook details
PUT    /api/v1/apps/:app_id/webhooks/:id  # Update webhook
DELETE /api/v1/apps/:app_id/webhooks/:id  # Delete webhook
GET    /api/v1/apps/:app_id/webhooks/:id/deliveries  # List delivery history
POST   /api/v1/apps/:app_id/webhooks/:id/test  # Send test webhook
```

#### Relationship Health
```
GET    /api/v1/health/summary     # Dashboard summary (entities needing attention)
GET    /api/v1/health/digest      # Weekly digest data
PUT    /api/v1/entities/:id/health-threshold  # Set custom threshold
```

#### Conversations
```
GET    /api/v1/conversations      # List conversations (with filters: channel, entity, archived)
GET    /api/v1/conversations/:id  # Get conversation with messages
PUT    /api/v1/conversations/:id  # Update conversation (archive, subject)
DELETE /api/v1/conversations/:id  # Delete conversation
GET    /api/v1/entities/:id/conversations  # List conversations for entity
```

#### Groups
```
GET    /api/v1/groups             # List user's groups
POST   /api/v1/groups             # Create group (static or smart)
GET    /api/v1/groups/:id         # Get group with members
PUT    /api/v1/groups/:id         # Update group
DELETE /api/v1/groups/:id         # Delete group
POST   /api/v1/groups/:id/entities      # Add entities to group
DELETE /api/v1/groups/:id/entities/:entity_id  # Remove entity from group
GET    /api/v1/groups/:id/entities      # List entities in group
```

#### Attachments
```
POST   /api/v1/attachments        # Upload attachment (multipart)
GET    /api/v1/attachments/:id    # Get attachment metadata
DELETE /api/v1/attachments/:id    # Delete attachment
GET    /api/v1/attachments/:id/download  # Download attachment file
GET    /api/v1/entities/:id/attachments  # List attachments for entity
```

#### User Preferences
```
GET    /api/v1/users/me/preferences      # Get all preferences
PUT    /api/v1/users/me/preferences      # Update preferences
GET    /api/v1/users/me/notifications    # Get notification settings
PUT    /api/v1/users/me/notifications    # Update notification settings
```

#### Activity Log (for user's own data)
```
GET    /api/v1/activity           # List recent activity (own actions)
GET    /api/v1/entities/:id/activity    # Activity for specific entity
```

### 4.4 API Documentation
- OpenAPI/Swagger specification
- Interactive API explorer
- Code examples in multiple languages
- SDK libraries (JavaScript, Python, mobile)
- Webhook documentation

---

## 5. Non-Functional Requirements

### 5.1 Security
- All data encrypted at rest and in transit (TLS 1.3+)
- Sensitive data (SSN, passwords) additionally encrypted
- Regular security audits
- OWASP compliance
- GDPR/CCPA compliance
- SOC 2 compliance (target)

### 5.2 Performance
- API response time < 200ms (95th percentile)
- Support 10,000+ entities per user
- Real-time communication latency < 500ms
- 99.9% uptime SLA

### 5.3 Scalability
- Horizontal scaling capability
- Multi-region deployment ready
- Database sharding strategy
- CDN for static assets

### 5.4 Privacy
- User data ownership and portability
- Granular privacy controls
- Data deletion capabilities (right to be forgotten)
- Audit logs for data access
- Consent management

---

## 6. User Interface Requirements

### 6.1 Web Application

#### 6.1.1 Core Views
| View | Description |
|------|-------------|
| Dashboard | Overview of recent activity, quick actions |
| Entity List | Browsable, searchable list of all entities |
| Entity Detail | Full entity profile with all information |
| Communication Center | Unified inbox and messaging |
| Timeline | Chronological interaction history |
| Settings | Account, privacy, and app settings |

#### 6.1.2 UI/UX Principles
- Responsive design (desktop, tablet, mobile web)
- Accessible (WCAG 2.1 AA compliance)
- Intuitive navigation
- Quick search always available
- Keyboard shortcuts for power users

#### 6.1.3 Onboarding Flow (Critical for Adoption)
New users complete a guided setup wizard:

| Step | Action | Purpose |
|------|--------|---------|
| 1. Welcome | Brief product intro, value proposition | Set expectations |
| 2. Profile Setup | Name, photo, timezone | Personalization |
| 3. Import Contacts | Connect Google/upload CSV (skip option) | Immediate value - populate with existing contacts |
| 4. Create First Entity | Guided creation if no import | Teach core interaction |
| 5. Set First Reminder | Suggest follow-up for imported contact | Demonstrate reminder value |
| 6. Tour Dashboard | Highlight key features, quick actions | Orientation |

**Onboarding Success Criteria:**
- < 3 minutes to complete
- 70%+ users import contacts during onboarding
- 50%+ users set at least one reminder during onboarding

#### 6.1.4 Duplicate Detection UX
When creating or editing an entity:
- Real-time duplicate checking as user types name/email/phone
- Warning modal showing potential duplicates with match confidence
- Options: "Create anyway", "View existing", "Merge with existing"

### 6.2 Future Platforms
- iOS native app
- Android native app
- Desktop app (Electron or native)
- Browser extension

---

## 7. Data Model (Conceptual)

### 7.1 Core Entities

```
User
├── id (UUID)
├── email
├── name
├── avatar_url
├── timezone
├── created_at
├── settings (JSON)
└── auth_providers[]

Entity
├── id (UUID)
├── owner_id (User)                    # User who created this entity
├── type (enum: person, organization, service, thing, animal, abstract)
├── name
├── description
├── avatar_url
├── metadata (JSON)
├── last_interaction_at               # For relationship health tracking
├── created_at
├── updated_at
└── archived_at

Relationship
├── id (UUID)
├── user_id (User)                     # User who owns this relationship
├── entity_id (Entity)                 # The entity this relationship describes
├── type (enum: friend, family, colleague, client, vendor, etc.)
├── strength (enum: close, regular, acquaintance)
├── status (enum: active, inactive, archived)
├── started_at
├── health_threshold_days             # Custom "losing touch" threshold
├── notes
└── created_at

Tag
├── id (UUID)
├── user_id (User)
├── name
├── color
├── description
└── created_at

EntityTag (join table)
├── entity_id (Entity)
├── tag_id (Tag)
└── created_at

Identifier
├── id (UUID)
├── entity_id (Entity)
├── type (enum: phone, email, ssn, government_id, account_number, social_handle, etc.)
├── value (encrypted for sensitive types)
├── label (e.g., "Work", "Personal", "Mobile")
├── is_primary
├── verified_at
└── created_at

Conversation
├── id (UUID)
├── user_id (User)
├── entity_id (Entity)
├── channel (enum: internal, email, sms, whatsapp, etc.)
├── subject
├── last_message_at
├── is_archived
└── created_at

Communication
├── id (UUID)
├── conversation_id (Conversation)     # For threading
├── user_id (User)
├── entity_id (Entity)
├── channel (enum: internal, email, phone, sms, etc.)
├── direction (enum: inbound, outbound)
├── content
├── attachments[] (JSON)
├── sent_at
└── read_at

Interaction
├── id (UUID)
├── user_id (User)
├── entity_id (Entity)
├── type (enum: note, meeting, call, transaction, etc.)
├── title
├── content
├── occurred_at
└── created_at

Reminder
├── id (UUID)
├── user_id (User)
├── entity_id (Entity, nullable)       # Can be entity-specific or standalone
├── type (enum: follow_up, birthday, anniversary, custom, health_alert)
├── title
├── description
├── due_at
├── recurrence_rule (JSON, nullable)   # For recurring reminders (RFC 5545 RRULE)
├── notification_channels[] (enum: in_app, email, push)
├── snoozed_until (nullable)
├── completed_at (nullable)
└── created_at

ExternalAccount
├── id (UUID)
├── user_id (User)
├── entity_id (Entity, nullable)
├── service_name
├── account_identifier
├── credentials (encrypted)
├── status (enum: connected, disconnected, error)
├── last_synced_at
└── created_at

ImportJob
├── id (UUID)
├── user_id (User)
├── source (enum: google, csv, vcard, linkedin, icloud, outlook)
├── status (enum: pending, processing, completed, failed)
├── total_records
├── processed_records
├── created_records
├── merged_records
├── error_log (JSON)
├── started_at
├── completed_at
└── created_at

Group
├── id (UUID)
├── user_id (User)
├── name
├── description
├── is_smart (boolean)                 # Smart groups auto-populate based on rules
├── rules (JSON, nullable)             # For smart groups: filter criteria
├── created_at
└── updated_at

EntityGroup (join table)
├── entity_id (Entity)
├── group_id (Group)
└── added_at

Attachment
├── id (UUID)
├── user_id (User)
├── entity_id (Entity, nullable)
├── interaction_id (Interaction, nullable)
├── communication_id (Communication, nullable)
├── filename
├── mime_type
├── size_bytes
├── storage_url
├── created_at
└── deleted_at

ActivityLog
├── id (UUID)
├── user_id (User)
├── action (enum: create, update, delete, view, export, login, etc.)
├── resource_type (enum: entity, relationship, communication, etc.)
├── resource_id (UUID)
├── metadata (JSON)                    # Additional context
├── ip_address
├── user_agent
└── created_at
```

### 7.2 Platform Entities (Third-Party App Support)

```
Application
├── id (UUID)
├── developer_id (User)               # Developer who registered the app
├── name
├── description
├── logo_url
├── website_url
├── callback_urls[] (JSON)
├── api_key (hashed)
├── api_secret (hashed)
├── scopes[] (enum: read_entities, write_entities, read_communications, etc.)
├── status (enum: pending, approved, suspended)
├── created_at
└── updated_at

ApplicationUser
├── id (UUID)
├── application_id (Application)
├── user_id (User)
├── external_user_id                  # User ID in the third-party app
├── granted_scopes[]
├── authorized_at
└── last_accessed_at

Webhook
├── id (UUID)
├── application_id (Application)
├── url
├── events[] (enum: entity.created, entity.updated, communication.sent, etc.)
├── secret (for signature verification)
├── status (enum: active, paused, failed)
├── last_triggered_at
├── failure_count
└── created_at

WebhookDelivery
├── id (UUID)
├── webhook_id (Webhook)
├── event_type
├── payload (JSON)
├── response_status
├── response_body
├── delivered_at
└── created_at
```

---

## 8. Implementation Phases

### Phase 1: MVP (Core Platform)
- Google OAuth authentication
- Basic entity CRUD operations (all entity types)
- Relationship management with tags
- Notes and interaction history
- Basic reminders (follow-up, date-based)
- Google Contacts import + CSV/vCard import
- Core API endpoints
- Basic web UI with responsive design
- Relationship health indicators (basic)

### Phase 2: Communication & Reminders
- Internal messaging system
- Email integration (send/receive)
- Communication history and threading
- Unified inbox
- Full reminder system with recurrence
- Push notifications
- Relationship health alerts and weekly digest
- Calendar integration (Google Calendar, Outlook) - sync meetings to interactions
- Groups and smart groups

### Phase 3: Enhanced Features
- Additional auth providers (Apple, email/password)
- Identifier management with deduplication
- Entity merging with conflict resolution
- LinkedIn import
- Advanced search (including natural language)
- Smart suggestions (AI-powered follow-ups)

### Phase 4: Platform Services
- Third-party app registration
- API keys and scopes
- Webhook system
- SDK libraries (JavaScript, Python)
- Developer portal and documentation
- Auto-enrichment from public data

### Phase 5: Mobile & Extensions
- iOS native app
- Android native app
- Browser extension (contact capture)
- Desktop app (Electron)
- Offline support with sync

---

## 9. Pricing Model

### 9.1 Tier Structure

| Tier | Price | Limits | Target User |
|------|-------|--------|-------------|
| **Free** | $0/mo | 100 entities, 500 interactions/mo, basic reminders | Individual trying the product |
| **Personal** | $9/mo | Unlimited entities, unlimited interactions, all reminder types, import/export | Active networker, freelancer |
| **Professional** | $19/mo | Everything in Personal + API access (1,000 calls/day), 2 connected apps | Power user, small business |
| **Team** | $12/user/mo | Everything in Professional + shared entities, team workspace, admin controls | Small teams (min 3 users) |
| **Enterprise** | Custom | Unlimited API, SSO/SAML, dedicated support, custom integrations, SLA | Large organizations |

### 9.2 Platform/API Pricing (for Third-Party Apps)

| Tier | Price | API Calls | Webhooks | Support |
|------|-------|-----------|----------|---------|
| **Developer** | Free | 1,000/day | 2 | Community |
| **Startup** | $49/mo | 50,000/day | 10 | Email |
| **Scale** | $199/mo | 500,000/day | Unlimited | Priority |
| **Enterprise** | Custom | Unlimited | Unlimited | Dedicated |

### 9.3 Add-ons
- Additional API calls: $10 per 10,000 calls
- Priority support: $29/mo
- Data enrichment credits: $20 per 1,000 enrichments
- White-label option: Enterprise only

---

## 10. Success Metrics

### 10.1 User Metrics
| Metric | Target | Phase |
|--------|--------|-------|
| User registration completion rate | > 80% | MVP |
| Daily active users / Monthly active users | > 30% | MVP |
| Average entities per active user | > 50 | MVP |
| Contacts imported on signup | > 70% of users | MVP |
| User retention (30-day) | > 40% | MVP |
| Free to paid conversion | > 5% | Phase 2 |

### 10.2 Product Metrics
| Metric | Target | Phase |
|--------|--------|-------|
| Reminders set per active user | > 5/month | Phase 2 |
| Communications sent through platform | > 10/user/month | Phase 2 |
| Entities with complete profiles | > 60% | Phase 3 |
| Search usage | > 3x/user/week | Phase 3 |

### 10.3 Platform Metrics
| Metric | Target | Phase |
|--------|--------|-------|
| Third-party app registrations | > 50 | Phase 4 |
| Active third-party apps | > 10 | Phase 4 |
| API uptime | 99.9% | All |
| API response time (p95) | < 200ms | All |

### 10.4 Business Metrics
| Metric | Target | Phase |
|--------|--------|-------|
| Monthly recurring revenue (MRR) | $10K | 6 months post-MVP |
| Customer acquisition cost (CAC) | < $50 | Phase 2 |
| Lifetime value (LTV) | > $200 | Phase 2 |
| LTV:CAC ratio | > 4:1 | Phase 3 |

---

## 11. Glossary

| Term | Definition |
|------|------------|
| Entity | Any person, organization, service, thing, or concept that a user has a relationship with |
| Relationship | The connection between a user and an entity, including type, strength, and metadata |
| Identifier | A unique piece of information that identifies an entity (phone, email, SSN, etc.) |
| Interaction | Any recorded event or note related to an entity |
| Communication | A message or conversation with an entity through any channel |
| Conversation | A threaded collection of communications with an entity on a specific channel |
| Reminder | A scheduled alert to take action, optionally linked to an entity |
| Relationship Health | A measure of how recently/frequently a user has interacted with an entity |
| Tag | A user-defined label for categorizing and filtering entities |
| Group | A collection of entities, either manually curated or auto-populated via smart rules |
| Smart Group | A group that automatically includes entities matching specified filter criteria |
| Conezia-powered app | A third-party application that uses Conezia as its backend for user and relationship management |
| Webhook | An HTTP callback that notifies third-party apps of events in Conezia |
| Enrichment | Automatically adding public information to an entity profile |

---

## 12. Open Questions

### Resolved (by this document)
| Question | Resolution |
|----------|------------|
| ~~Monetization model?~~ | Freemium with Personal ($9), Professional ($19), Team ($12/user), Enterprise tiers |
| ~~Data Portability formats?~~ | CSV, vCard 4.0, JSON, PDF export supported |

### Pending Decisions

#### Product Decisions
1. **Data Sharing Between Users**: How should entities be shared between Conezia users who know the same real-world person?
   - Option A: No sharing - each user maintains separate entity records
   - Option B: Opt-in sharing - users can "connect" their entity records
   - Option C: Global entity registry with privacy controls
   - *Recommendation*: Start with Option A for MVP, evolve to Option B

2. **Identifier Verification**: Should entity identifiers (phone, email) be verifiable?
   - If yes: SMS/email verification flow, verification badge
   - *Recommendation*: Optional verification, not required

3. **Offline Support Strategy**: What level of offline support?
   - Option A: Web-only, no offline
   - Option B: PWA with read-only offline
   - Option C: Full offline with sync (mobile-first)
   - *Recommendation*: Option B for web, Option C for native mobile apps

4. **AI Provider**: Build in-house ML or use third-party AI APIs?
   - Options: OpenAI, Anthropic, self-hosted models, hybrid
   - *Consideration*: Privacy implications of sending user data to third parties

#### Technical Decisions
5. **Technology Stack**: What backend/frontend technologies?
   - Backend options: Node.js, Python/Django, Elixir/Phoenix, Go
   - Frontend options: React, Vue, Svelte
   - Database: PostgreSQL (recommended), with Redis for caching
   - *Recommendation*: Defer to design phase

6. **Real-time Architecture**: WebSockets vs Server-Sent Events vs polling?
   - For: Internal chat, notifications, sync
   - *Recommendation*: WebSockets for chat, SSE for notifications

7. **Multi-tenancy Model**: Shared database vs database-per-tenant?
   - *Recommendation*: Shared database with row-level security for MVP, evaluate for Enterprise

#### Business Decisions
8. **Open Source Strategy**: Should any component be open-source?
   - Option A: Fully proprietary
   - Option B: Open-source core, proprietary add-ons (like Monica)
   - Option C: Open API specification only
   - *Consideration*: Open source builds trust for privacy-sensitive users

9. **Geographic Rollout**: Which regions first?
   - Data residency requirements (GDPR, etc.)
   - *Recommendation*: US first, EU second (with EU data center)

10. **Third-Party Integration Priority**: Which integrations first beyond Google?
    - LinkedIn (high demand but limited API)
    - Apple iCloud (iOS user base)
    - Microsoft/Outlook (enterprise users)
    - WhatsApp Business API (communication)
    - *Recommendation*: Prioritize based on user research

---

## 13. Appendix: Competitive Positioning

### Key Differentiators vs Competitors
| Feature | Conezia | Monica | Dex | Clay |
|---------|---------|--------|-----|------|
| Universal entity types | ✅ | ❌ People only | ❌ People only | ❌ People only |
| Platform-as-service | ✅ | ❌ | ❌ | ❌ |
| Unified communication | ✅ Send/receive | ❌ Track only | ❌ Track only | ❌ Track only |
| Open API | ✅ Full | ⚠️ Limited | ❌ | ❌ |
| Self-host option | 🔄 TBD | ✅ | ❌ | ❌ |
| AI features | ✅ | ❌ | ✅ | ✅ |
| Free tier | ✅ 100 entities | ✅ 10 contacts | ⚠️ Trial | ✅ 1K contacts |

### Target User Personas
1. **The Networker**: Freelancer/consultant managing 500+ professional contacts
2. **The Life Organizer**: Individual wanting to track all life relationships and services
3. **The Developer**: Building an app that needs user/relationship management
4. **The Small Team**: Agency or firm with shared client relationships

---

*Document Version: 2.1*
*Created: 2026-01-17*
*Last Updated: 2026-01-17*

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-17 | Initial requirements based on prep.md |
| 2.0 | 2026-01-17 | Added reminders, import/export, AI features, pricing, competitive analysis |
| 2.1 | 2026-01-17 | Final review: Added onboarding flow, groups, calendar integration, missing API endpoints (conversations, groups, attachments, preferences, activity), fixed data model (user_id on Relationship, Group, Attachment, ActivityLog entities) |
