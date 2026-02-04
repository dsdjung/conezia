# Conezia Product Strategy

*"YourLifeConnected"*

---

## 1. Executive Summary

Conezia is a personal relationship management (PRM) platform that gives individuals a single, unified hub for managing every connection in their lives - people, organizations, services, possessions, and more. Unlike CRMs built for sales teams, Conezia is built for humans managing the full breadth of their personal and professional relationships.

The product operates on two layers: a standalone consumer application and a platform-as-a-service that third-party developers can build upon. This dual-mode architecture positions Conezia to capture value both directly from end users and from the ecosystem of applications that leverage its relationship infrastructure.

---

## 2. The Problem

### 2.1 Fragmented Relationship Data

Modern individuals maintain relationships across dozens of disconnected systems:
- Phone contacts hold numbers but no context
- Email clients store conversations but lack relationship metadata
- Calendar apps track meetings but not who matters
- Social media shows activity but not relationship health
- Spreadsheets and notes apps become graveyards of forgotten follow-ups

The result: people lose touch with important connections, forget commitments, miss life events, and lack a coherent view of the relationships that shape their lives.

### 2.2 The CRM Gap

Existing CRMs (Salesforce, HubSpot) are built for sales pipelines, not personal relationships. They optimize for deal closure, not relationship health. The few personal CRMs that exist (Monica, Dex, Clay) treat relationships as people-only and lack the breadth to capture the full spectrum of connections a modern person manages - their vet, their insurance policy, their car, their community group.

### 2.3 No Relationship Platform Exists

Developers building apps that involve users and relationships (event planning, gift giving, community management, mentorship) must rebuild user management, contact storage, and relationship logic from scratch. There is no foundational platform that provides relationship infrastructure as a service.

---

## 3. Target Users

### 3.1 Primary Personas

| Persona | Description | Pain Point | Willingness to Pay |
|---------|-------------|------------|-------------------|
| **The Networker** | Freelancer or consultant managing 500+ professional contacts | Losing track of warm leads and referral sources; missing follow-ups that cost them business | High ($19/mo) |
| **The Life Organizer** | Individual who wants a single system for all relationships and life admin | Scattered contact info, forgotten birthdays, no record of service providers or important dates | Medium ($9/mo) |
| **The Developer** | Builder creating apps that need user and relationship management | Rebuilding auth, contact storage, and relationship logic for every new project | High ($49-199/mo API) |
| **The Small Team** | Agency or firm with shared client relationships | No shared source of truth for client relationships and interaction history | High ($12/user/mo) |

### 3.2 Beachhead Market

**The Networker** is the initial target. This persona:
- Has an acute, recurring pain (missed follow-ups = lost revenue)
- Is willing to pay for tools that protect their network
- Is vocal about tools they use (organic distribution)
- Already searches for "personal CRM" solutions
- Represents a large, growing freelancer/creator economy (70M+ in the US alone)

### 3.3 Expansion Path

Networker -> Life Organizer -> Developer -> Small Team -> Enterprise

Each segment validates and funds the next. Networkers prove the core product. Life Organizers prove breadth beyond professional use. Developers prove the platform layer. Teams prove multi-user collaboration.

---

## 4. Competitive Landscape

### 4.1 Direct Competitors

| Product | Model | Strengths | Weaknesses |
|---------|-------|-----------|------------|
| **Monica** | Open-source PRM | Self-hostable, privacy-focused, free tier | People-only, no communication integration, dated UI, slow development |
| **Dex** | SaaS PRM | Clean UI, LinkedIn integration, mobile app | People-only, no API, limited free tier, no calendar sync |
| **Clay** | AI-powered PRM | Strong auto-enrichment, AI suggestions, email integration | People-only, expensive ($20-180/mo), enterprise-oriented, no platform play |
| **Folk** | CRM/PRM hybrid | Flexible data model, team features, Chrome extension | Sales-oriented, no relationship health, no universal entity types |

### 4.2 Indirect Competitors

| Product | Overlap | Why Users Leave |
|---------|---------|-----------------|
| **Google Contacts** | Contact storage | No relationship context, no reminders, no interaction history |
| **Apple Contacts** | Contact storage | Same limitations as Google Contacts |
| **Notion** | Flexible data organization | Too generic, no relationship-specific features, no integrations |
| **Airtable** | Customizable database | Requires manual setup, no built-in sync, no health scoring |
| **Spreadsheets** | DIY contact management | No automation, no sync, no notifications, breaks at scale |

### 4.3 Competitive Moat

Conezia's defensibility comes from three compounding advantages:

1. **Universal Entity Model**: Supporting 6 entity types (people, organizations, services, things, animals, abstract) creates a richer data graph than any competitor. Once a user has tracked their relationships, service providers, possessions, and life events in one place, switching costs are very high.

2. **Platform-as-a-Service**: The API and webhook infrastructure allow third-party apps to build on Conezia's relationship layer. Each app built on the platform increases the value of the core data and creates ecosystem lock-in that competitors cannot replicate by adding features.

3. **Two-Way Integration Depth**: Deep bidirectional sync with Google Calendar, iCloud, Gmail, and other services means Conezia becomes the canonical source of truth. Competitors that only import (one-way) cannot match this.

---

## 5. Value Proposition

### 5.1 Core Promise

**"Never lose touch with anyone or anything that matters."**

### 5.2 Value by Persona

| Persona | Value | Metric |
|---------|-------|--------|
| Networker | "My network is my livelihood. Conezia makes sure no relationship falls through the cracks." | Follow-ups completed, connections maintained |
| Life Organizer | "One place for every relationship in my life - my doctor, my mechanic, my friends, my subscriptions." | Entities tracked, reminders acted on |
| Developer | "I get user management, contact storage, and relationship logic out of the box. I just build my app." | Time to ship, API calls per day |
| Small Team | "Our whole team sees the same view of every client relationship." | Team alignment, client satisfaction |

### 5.3 Why Conezia Over Alternatives

| Alternative | Conezia Advantage |
|-------------|-------------------|
| vs Monica | Modern UI, two-way sync, universal entities, active development, platform API |
| vs Dex | Universal entities (not just people), open API, calendar sync, self-host option planned |
| vs Clay | Affordable pricing, universal entities, platform-as-service, privacy-first (encrypted at rest) |
| vs Notion/Airtable | Purpose-built for relationships, automatic health scoring, native integrations, zero setup |
| vs Spreadsheets | Automated reminders, sync with external calendars, duplicate detection, relationship health scoring |

---

## 6. Product Strategy

### 6.1 Strategic Pillars

**Pillar 1: Capture** - Make it effortless to get all relationships into Conezia
- One-click import from Google, iCloud, LinkedIn, CSV, vCard
- Two-way calendar sync to auto-create events
- Browser extension to capture contacts from the web (future)
- Mobile app for on-the-go capture (future)

**Pillar 2: Connect** - Surface insights that strengthen relationships
- Relationship health scoring with configurable thresholds
- Smart reminders and weekly digests
- AI-powered follow-up suggestions (future)
- Meeting prep briefs from interaction history (future)

**Pillar 3: Communicate** - Enable action directly from Conezia
- Unified inbox across email, SMS, and messaging platforms
- Click-to-call, click-to-email from entity profiles
- Event creation linked to entities
- Gift tracking tied to occasions and relationships

**Pillar 4: Platform** - Make Conezia the relationship layer for the internet
- Full REST API with comprehensive documentation
- Webhook system for real-time event notifications
- SDK libraries for common languages
- Developer portal with usage analytics

### 6.2 Product Roadmap

#### Phase 1: Foundation (Current - ~80% Complete)
- Entity management (6 types) with relationships, tags, groups
- Interaction history and notes
- Reminders with recurrence and health scoring
- Google OAuth + contact import
- Events with calendar sync (Google, iCloud)
- Gift tracking
- Core REST API (50+ endpoints)
- Web UI with LiveView

#### Phase 2: Communication & Integration
- Unified inbox (email, internal messaging)
- Gmail send/receive integration
- External service connection UI flow
- Email/password authentication
- Push notifications
- Entity merge with conflict resolution
- LinkedIn import
- Enhanced duplicate detection

#### Phase 3: Intelligence
- AI-powered follow-up suggestions
- Natural language search
- Auto-enrichment from public data
- Meeting prep briefs
- Smart group recommendations
- Contact change detection (job changes, moves)

#### Phase 4: Platform
- Developer portal with documentation
- SDK libraries (JavaScript, Python)
- App marketplace
- Third-party app review and approval
- Usage analytics and billing
- White-label options

#### Phase 5: Expansion
- iOS native app
- Android native app
- Browser extension (contact capture)
- Offline support with sync
- Team workspaces with permissions
- SSO/SAML for enterprise

### 6.3 Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data sharing between users | No sharing (MVP), opt-in sharing later | Privacy first. Multi-user sharing adds complexity before product-market fit is proven |
| AI provider | Third-party API (Anthropic/OpenAI) with user consent | Faster time to market. Privacy managed via opt-in and data minimization |
| Offline strategy | PWA with read-only offline (web), full offline (mobile) | Web users expect connectivity. Mobile users need offline access |
| Open source | Evaluate post-product-market-fit | Open source builds trust for privacy-sensitive users but complicates monetization. Decide after validating paid demand |
| Geographic rollout | US first, EU second | Regulatory simplicity. EU requires data residency which adds infrastructure cost |

---

## 7. Business Model

### 7.1 Revenue Streams

**Stream 1: Consumer Subscriptions** (Primary, Phase 1-2)

| Tier | Price | Key Limits | Target |
|------|-------|------------|--------|
| Free | $0/mo | 100 entities, 500 interactions/mo | Trial users |
| Personal | $9/mo | Unlimited entities, all reminder types, import/export | Active networkers |
| Professional | $19/mo | + API access (1,000 calls/day), 2 connected apps | Power users |
| Team | $12/user/mo | + Shared entities, team workspace, admin controls | Small teams (min 3) |
| Enterprise | Custom | Unlimited API, SSO/SAML, dedicated support, SLA | Large organizations |

**Stream 2: Platform API** (Secondary, Phase 3-4)

| Tier | Price | API Calls | Webhooks |
|------|-------|-----------|----------|
| Developer | Free | 1,000/day | 2 |
| Startup | $49/mo | 50,000/day | 10 |
| Scale | $199/mo | 500,000/day | Unlimited |
| Enterprise | Custom | Unlimited | Unlimited |

**Stream 3: Add-ons** (Supplemental, Phase 3+)
- Additional API calls: $10 per 10,000
- Data enrichment credits: $20 per 1,000
- Priority support: $29/mo
- White-label: Enterprise only

### 7.2 Unit Economics Targets

| Metric | Target | Timeline |
|--------|--------|----------|
| Customer Acquisition Cost (CAC) | < $50 | 6 months post-launch |
| Lifetime Value (LTV) | > $200 | 12 months post-launch |
| LTV:CAC Ratio | > 4:1 | 12 months post-launch |
| Monthly Recurring Revenue (MRR) | $10K | 6 months post-launch |
| Free to Paid Conversion | > 5% | Phase 2 |
| Gross Margin | > 80% | Phase 2 |

### 7.3 Pricing Philosophy

- Free tier is generous enough to demonstrate value (100 entities) but limited enough to encourage upgrade (no API, limited interactions)
- Personal tier ($9/mo) is priced below Clay ($20/mo) and competitive with Dex ($12/mo) to win on value
- API pricing creates a second revenue axis independent of consumer subscriptions
- No per-entity pricing. Relationship management should not penalize users for having more connections.

---

## 8. Go-to-Market Strategy

### 8.1 Launch Strategy

**Pre-Launch (Build Waitlist)**
- Landing page with clear value proposition and email capture
- Content marketing: "Why Your Address Book Is Not Enough" blog series
- ProductHunt submission prepared
- Beta program with 50-100 early users from target persona (freelancers, consultants)

**Launch (Public Availability)**
- ProductHunt launch with demo video
- Hacker News "Show HN" post (developer audience for platform angle)
- Reddit posts in r/productivity, r/freelance, r/entrepreneur
- Twitter/X announcement thread
- Email to waitlist with free Personal tier for first month

**Post-Launch (Growth)**
- Content marketing (SEO)
- Integration partnerships
- Developer relations for platform adoption
- Community building

### 8.2 Marketing Channels

| Channel | Purpose | Priority | Cost |
|---------|---------|----------|------|
| **Content/SEO** | Long-term organic acquisition | High | Low (time investment) |
| **ProductHunt** | Launch spike and early adopter acquisition | High | Free |
| **Twitter/X** | Community building, thought leadership | High | Free |
| **Reddit** | Community engagement, feedback | Medium | Free |
| **YouTube** | Product demos, use-case walkthroughs | Medium | Low |
| **Partnerships** | Integration co-marketing (Google Workspace, etc.) | Medium | Free |
| **Paid Search** | "personal CRM" keywords | Low (initially) | $5-15 per click |
| **Developer Blog** | Platform adoption, API tutorials | Medium | Low |

### 8.3 Content Strategy

**Themes (mapped to personas):**

1. **Networking & Relationship Building** (Networker persona)
   - "How top consultants manage 500+ client relationships"
   - "The follow-up framework that 10x'd my referral business"
   - "Why your CRM is failing your personal network"

2. **Life Organization** (Life Organizer persona)
   - "Track every relationship in your life, not just people"
   - "Never forget a birthday, anniversary, or follow-up again"
   - "From scattered contacts to a unified life dashboard"

3. **Developer Platform** (Developer persona)
   - "Build a relationship-aware app in a weekend"
   - "Why every app needs a relationship layer"
   - API tutorials and integration guides

4. **Product Comparisons** (All personas)
   - "Conezia vs Monica: Which personal CRM is right for you?"
   - "Why spreadsheets break at 100 contacts"
   - "The personal CRM landscape in 2026"

### 8.4 Distribution Advantages

1. **Import-driven virality**: Users who import Google Contacts immediately see value, reducing time-to-aha
2. **Calendar sync creates daily touchpoints**: Two-way sync means Conezia surfaces in daily workflows
3. **Reminder emails drive re-engagement**: Health alerts and follow-up reminders bring users back without paid re-targeting
4. **API ecosystem effects**: Each app built on the platform brings its users into the Conezia ecosystem

---

## 9. Success Metrics

### 9.1 North Star Metric

**Weekly Active Relationships Managed** - The number of unique entities a user interacts with (views, notes, reminders, communications) per week. This metric captures both engagement depth and breadth.

### 9.2 Phase-Specific KPIs

#### Phase 1-2 (Product-Market Fit)

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| Registration completion rate | > 80% | Onboarding friction |
| Contacts imported on signup | > 70% of users | Immediate value delivery |
| DAU/MAU ratio | > 30% | Habitual usage |
| Average entities per active user | > 50 | Data investment (switching cost) |
| 30-day retention | > 40% | Product-market fit signal |
| NPS | > 40 | User satisfaction and word-of-mouth potential |

#### Phase 3-4 (Growth & Platform)

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| Free to paid conversion | > 5% | Monetization efficiency |
| Reminders acted on per user/month | > 5 | Feature engagement |
| API registrations | > 50 apps | Platform traction |
| Active third-party apps | > 10 | Ecosystem health |
| MRR | $10K | Business sustainability |

#### Phase 5 (Scale)

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| LTV:CAC ratio | > 4:1 | Growth efficiency |
| Gross margin | > 80% | Business health |
| Revenue from platform API | > 20% of total | Revenue diversification |
| Enterprise customers | > 10 | Market expansion |

---

## 10. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Google/Apple restrict API access** | Medium | High | Support CSV/vCard import as fallback; build direct integrations where possible; diversify import sources |
| **Privacy concerns deter adoption** | Medium | High | Encryption at rest, transparent data practices, GDPR/CCPA compliance, potential self-host option |
| **Low retention after import** | Medium | High | Focus on reminder/health features that create recurring value; optimize onboarding to set first reminder |
| **Platform/API doesn't gain traction** | Medium | Medium | Platform is a second-order bet. Consumer product must be viable standalone. Don't over-invest in platform before consumer PMF |
| **Competitor acquires or copies features** | Low | Medium | Speed of execution; depth of integration; ecosystem effects from platform; universal entity model is hard to retrofit |
| **AI features commoditized** | High | Low | AI is a feature accelerator, not the core value. Relationship data graph and integrations are the moat |
| **Team/enterprise features dilute focus** | Medium | Medium | Defer team features until consumer product-market fit is validated. Don't build for enterprises before individuals love the product |

---

## 11. Why Conezia, Why Now

### 11.1 Market Timing

1. **Remote work normalized relationship fragmentation**: With fewer in-person interactions, people need tools to maintain relationships deliberately rather than accidentally.

2. **Creator/freelancer economy explosion**: 70M+ Americans freelance. Each one is a solo operator managing their own network as their most valuable business asset.

3. **AI makes personal tools viable**: LLM-powered features (smart suggestions, natural language search, auto-enrichment) are now cheap and accessible enough to build into consumer products.

4. **API economy maturity**: Developers expect to compose applications from services. A relationship-as-a-service platform is overdue.

5. **Privacy backlash creates opportunity**: Growing distrust of big tech platforms creates demand for tools where users own their data, with potential for self-hosting.

### 11.2 Why This Team/Product

- Built on Elixir/Phoenix - a technology stack designed for real-time, concurrent, fault-tolerant applications (the exact requirements of a communication and relationship platform)
- Universal entity model designed from day one (not retrofitted onto a people-only CRM)
- Platform API built alongside the consumer product (not bolted on later)
- Privacy-first architecture with field-level encryption from the start

### 11.3 Vision

Conezia becomes the relationship layer of the internet - the canonical place where individuals and applications manage the connections that matter. Just as Stripe became the payment layer and Auth0 became the authentication layer, Conezia becomes the relationship layer that every application builds upon.

---

*Document Version: 1.0*
*Created: 2026-02-04*
