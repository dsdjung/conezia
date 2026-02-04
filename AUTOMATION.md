# Conezia Automation Stack

Full automation pipeline for strategy iteration, development, deployment, marketing, and operations.

---

## 1. Strategy Iteration & Product Intelligence

| Function | Build vs Buy | Tool/Approach |
|----------|-------------|---------------|
| User feedback collection | Buy | PostHog, Canny, or Intercom for in-app feedback |
| Analytics pipeline | Buy | PostHog (self-hostable, privacy-friendly) or Plausible |
| Competitor monitoring | Buy | Crayon, Klue, or custom RSS/scraper watching competitor changelogs |
| Strategy document versioning | Already have | Git-tracked STRATEGY.md + requirement.md with PR-based review |
| A/B testing framework | Build | Phoenix LiveView feature flags + PostHog experiments |
| User interviews/surveys | Buy | Typeform or Cal.com for scheduling + recording |
| Metrics dashboard | Build | LiveDashboard extension or Grafana pulling from PostHog/DB |

### What needs to be built

- A metrics collection layer in the app that tracks the KPIs defined in STRATEGY.md (weekly active relationships, import completion rate, retention)
- An automated weekly report that compares actual metrics against strategy targets

---

## 2. Development Automation

| Function | Build vs Buy | Tool/Approach |
|----------|-------------|---------------|
| CI/CD pipeline | Buy/Configure | GitHub Actions (already on GitHub) |
| Automated testing | Already have | `mix test` with 528 tests, needs CI integration |
| Code quality | Configure | Credo (Elixir linter), Dialyzer (type checking), `mix format` |
| Dependency updates | Buy | Dependabot or Renovate Bot |
| Database migrations | Already have | Ecto migrations, need CI validation |
| Preview environments | Build/Buy | Fly.io preview apps or Render PR previews |
| Error tracking | Buy | Sentry (Elixir SDK exists) |
| Performance monitoring | Buy | AppSignal (Elixir-native) or New Relic |
| Security scanning | Buy | Sobelow (Elixir security scanner), Snyk for deps |
| Release management | Build | `mix release` + Docker + automated tagging |

### GitHub Actions Pipeline

```
PR opened -> compile (warnings-as-errors) -> format check -> credo -> sobelow
          -> mix test -> dialyzer -> build Docker image -> deploy preview env

Merge to main -> all above -> build release -> deploy to staging
             -> run smoke tests -> deploy to production -> notify

Scheduled -> dependency audit -> security scan -> performance benchmarks
```

### What needs to be built

- `.github/workflows/ci.yml` - CI pipeline
- `.github/workflows/deploy.yml` - CD pipeline
- `Dockerfile` and `docker-compose.prod.yml` for production
- Smoke test suite that hits critical paths post-deploy
- Database migration safety checks (no destructive migrations without manual approval)

---

## 3. Deployment & Infrastructure

| Function | Build vs Buy | Tool/Approach |
|----------|-------------|---------------|
| Hosting | Buy | Fly.io (Elixir-native, global edge), Railway, or AWS ECS |
| Database hosting | Buy | Fly Postgres, Supabase, or AWS RDS |
| Redis | Buy | Upstash (serverless) or Fly Redis |
| File storage (S3) | Buy | AWS S3, Cloudflare R2, or Tigris |
| CDN | Buy | Cloudflare (free tier sufficient initially) |
| DNS | Buy | Cloudflare |
| SSL/TLS | Buy | Cloudflare or Let's Encrypt (auto) |
| Infrastructure as Code | Build | Terraform or Pulumi for reproducible infra |
| Secrets management | Buy | Fly secrets, AWS Secrets Manager, or Doppler |
| Uptime monitoring | Buy | BetterStack, Checkly, or UptimeRobot |
| Log aggregation | Buy | BetterStack Logs, Datadog, or self-hosted Loki |
| Backup automation | Build | Automated pg_dump to S3 on cron |

### What needs to be built

- Terraform/Pulumi configs for all infrastructure
- Automated database backup and restore verification
- Health check endpoint (`/healthz`) that validates DB + Redis connectivity
- Runbook for incident response (automated alerting -> PagerDuty/Opsgenie)
- Blue/green or rolling deployment strategy
- Auto-scaling rules based on CPU/memory/request latency

---

## 4. Marketing Automation

| Function | Build vs Buy | Tool/Approach |
|----------|-------------|---------------|
| Landing page | Build | Phoenix LiveView page at root domain, or separate Next.js site |
| Email marketing | Buy | Resend, Postmark, or Loops (developer-friendly) |
| Transactional email | Buy | Resend or Postmark (same provider as marketing) |
| Blog/Content | Build/Buy | Ghost (self-hosted), or markdown files rendered by Phoenix |
| SEO monitoring | Buy | Ahrefs, Semrush, or Google Search Console (free) |
| Social scheduling | Buy | Buffer, Typefully (for Twitter/X), or manual |
| ProductHunt launch | Manual | Prepare assets, schedule launch day |
| Waitlist management | Build | Simple LiveView form + DB table + email integration |
| Referral program | Build | Invite codes with tracking in the app |
| Analytics attribution | Buy | PostHog or Plausible with UTM tracking |
| Drip email sequences | Buy | Loops, Customer.io, or Resend + custom Oban worker |

### What needs to be built

- Landing page with value proposition, demo video, and email capture
- Onboarding email sequence (welcome, tips, feature highlights, conversion nudge)
- Relationship health digest email (weekly, drives re-engagement for free)
- Blog rendering system (markdown -> HTML with SEO metadata)
- UTM parameter tracking through signup flow to measure channel effectiveness
- In-app prompts for upgrade at natural friction points (hitting 100 entity limit)

### Content Automation Pipeline

```
Write content (markdown) -> PR review -> merge -> auto-publish to blog
                         -> auto-generate social posts (manual review)
                         -> schedule via Buffer/Typefully
                         -> track performance via analytics
```

---

## 5. Operations & Customer Success

| Function | Build vs Buy | Tool/Approach |
|----------|-------------|---------------|
| Customer support | Buy | Plain.com (developer-focused), Intercom, or email-based |
| Knowledge base / docs | Build | ExDoc for API docs, markdown for help articles |
| Status page | Buy | BetterStack Status or Instatus |
| Billing & subscriptions | Buy | Stripe Billing (subscriptions, metered API usage) |
| Usage metering | Build | Oban worker tracking API calls, entity counts per user |
| Abuse/rate limit monitoring | Build | Extend existing rate limiter with alerting |
| GDPR/data requests | Build | Admin endpoint to export/delete all user data |
| Changelog | Build/Buy | Headway, or markdown changelog auto-published on deploy |
| Developer portal | Build | API docs (OpenAPI spec) + interactive explorer |

### What needs to be built

- Stripe integration for subscription management (checkout, portal, webhooks)
- Usage tracking system (entity count, API calls, interactions/month per user)
- Enforcement layer that checks limits before allowing operations
- Admin dashboard for user management, support, and operational metrics
- Automated GDPR data export/deletion endpoint
- API documentation generated from OpenAPI spec
- Webhook for Stripe events (subscription created, cancelled, payment failed)

---

## 6. Feedback Loop (Closing the Cycle)

The critical piece that connects operations back to strategy:

```
User behavior (PostHog) ─────────────────────────────┐
Support tickets (Plain) ──────────────────────────────┤
Churn reasons (cancellation survey) ──────────────────┤
Feature requests (Canny/in-app) ──────────────────────┤
Competitor changes (monitoring) ──────────────────────┤
Revenue metrics (Stripe) ─────────────────────────────┤
                                                      ▼
                                            Weekly Review
                                            (automated report)
                                                      │
                                                      ▼
                                         Strategy Update (STRATEGY.md PR)
                                                      │
                                                      ▼
                                         Backlog Prioritization
                                                      │
                                                      ▼
                                         Development Cycle
```

### What needs to be built

- Automated weekly metrics report comparing actuals to STRATEGY.md targets
- Cancellation survey (1-question on event form)
- NPS survey at 30/60/90 day marks (in-app)
- Aggregated feedback dashboard pulling from all sources

---

## Priority Order for Building

Given current state (product ~80% MVP, no infrastructure automation):

| Priority | What | Why |
|----------|------|-----|
| 1 | GitHub Actions CI/CD | Every subsequent change benefits from automated testing/deploy |
| 2 | Production deployment (Fly.io + Terraform) | Can't get users without being live |
| 3 | Stripe billing integration | Can't monetize without payments |
| 4 | PostHog analytics | Can't improve without measuring |
| 5 | Transactional email (Resend) | Needed for password reset, reminders, digests |
| 6 | Landing page + waitlist | Top of the marketing funnel |
| 7 | Error tracking (Sentry) | Know when things break before users report |
| 8 | Usage metering + limits | Enforce free tier, enable upgrade path |
| 9 | Onboarding email sequence | Drive activation and retention |
| 10 | Status page + uptime monitoring | Operational hygiene |

## Estimated Launch Costs (Pre-Revenue)

~$50-100/month total:

| Service | Cost |
|---------|------|
| Fly.io | $10-30/month |
| Resend | Free tier |
| PostHog | Free tier |
| Cloudflare | Free tier |
| Stripe | Transaction-based |
| Sentry | Free tier |
| BetterStack | Free tier |

---

*Document Version: 1.0*
*Created: 2026-02-04*
