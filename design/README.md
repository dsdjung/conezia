# Conezia Design Documents

This folder contains the technical design documentation for Conezia, a personal relationship management platform.

## Document Index

| Document | Description |
|----------|-------------|
| [01-architecture-overview.md](01-architecture-overview.md) | High-level system architecture, technology stack, Phoenix contexts, authentication, real-time features, and deployment topology |
| [02-database-schema.md](02-database-schema.md) | Complete PostgreSQL database schema with Ecto schemas, migrations, indexes, and relationships |
| [03-api-design.md](03-api-design.md) | REST API specification including all endpoints, request/response formats, and error handling |
| [04-validation-rules.md](04-validation-rules.md) | Comprehensive validation rules for all data inputs with Elixir code examples |
| [05-docker-infrastructure.md](05-docker-infrastructure.md) | Docker configuration for development, testing, and production environments |

## Technology Stack

- **Backend**: Elixir 1.16+ / Phoenix 1.7+
- **Database**: PostgreSQL 16
- **Cache**: Redis 7
- **File Storage**: S3-compatible (MinIO for dev, AWS S3 for prod)
- **Background Jobs**: Oban
- **Container Runtime**: Docker / Docker Compose

## Quick Start

```bash
# Clone and setup
git clone https://github.com/dsdjung/conezia.git
cd conezia

# Start development environment
make setup

# Or manually:
cp .env.dev .env
docker-compose up -d

# Access the application
open http://localhost:4000
```

## Design Principles

1. **Convention over Configuration** - Follow Phoenix/Elixir conventions
2. **Contexts for Domain Boundaries** - Separate business logic into bounded contexts
3. **Validate at the Boundary** - All external input validated via Ecto changesets
4. **Fail Fast** - Use pattern matching and guards liberally
5. **Database as Source of Truth** - Avoid distributed state where possible

## Related Documents

- [../requirement.md](../requirement.md) - Product requirements specification
- [../prep.md](../prep.md) - Initial product vision

---

*Document Version: 1.0*
*Created: 2026-01-17*
