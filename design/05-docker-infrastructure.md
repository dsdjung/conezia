# Conezia Docker Infrastructure

## 1. Overview

This document defines the Docker-based infrastructure for Conezia, including development, testing, and production configurations.

### 1.1 Container Stack

| Service | Image | Purpose |
|---------|-------|---------|
| **app** | Custom (Elixir) | Phoenix application |
| **postgres** | postgres:16-alpine | Primary database |
| **redis** | redis:7-alpine | Cache, sessions, pub/sub |
| **minio** | minio/minio | S3-compatible storage (dev) |
| **mailhog** | mailhog/mailhog | Email testing (dev) |

---

## 2. Development Environment

### 2.1 docker-compose.yml

```yaml
version: "3.8"

services:
  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    container_name: conezia_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-conezia}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-conezia_dev}
      POSTGRES_DB: ${POSTGRES_DB:-conezia_dev}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-conezia} -d ${POSTGRES_DB:-conezia_dev}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - conezia_network

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: conezia_redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - conezia_network

  # MinIO (S3-compatible storage)
  minio:
    image: minio/minio:latest
    container_name: conezia_minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-minioadmin}
    ports:
      - "${MINIO_API_PORT:-9000}:9000"
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
    volumes:
      - minio_data:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - conezia_network

  # MinIO client for bucket setup
  minio-setup:
    image: minio/mc:latest
    container_name: conezia_minio_setup
    depends_on:
      minio:
        condition: service_healthy
    entrypoint: >
      /bin/sh -c "
        mc alias set local http://minio:9000 ${MINIO_ROOT_USER:-minioadmin} ${MINIO_ROOT_PASSWORD:-minioadmin};
        mc mb --ignore-existing local/conezia-attachments;
        mc mb --ignore-existing local/conezia-exports;
        mc anonymous set download local/conezia-attachments;
        exit 0;
      "
    networks:
      - conezia_network

  # MailHog (email testing)
  mailhog:
    image: mailhog/mailhog:latest
    container_name: conezia_mailhog
    restart: unless-stopped
    ports:
      - "${MAILHOG_SMTP_PORT:-1025}:1025"
      - "${MAILHOG_UI_PORT:-8025}:8025"
    networks:
      - conezia_network

  # Phoenix Application (development)
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    container_name: conezia_app
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      MIX_ENV: dev
      DATABASE_URL: ecto://${POSTGRES_USER:-conezia}:${POSTGRES_PASSWORD:-conezia_dev}@postgres:5432/${POSTGRES_DB:-conezia_dev}
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:-dev_secret_key_base_that_is_at_least_64_bytes_long_for_development}
      PHX_HOST: localhost
      PHX_PORT: 4000
      S3_ENDPOINT: http://minio:9000
      S3_BUCKET: conezia-attachments
      AWS_ACCESS_KEY_ID: ${MINIO_ROOT_USER:-minioadmin}
      AWS_SECRET_ACCESS_KEY: ${MINIO_ROOT_PASSWORD:-minioadmin}
      SMTP_HOST: mailhog
      SMTP_PORT: 1025
    ports:
      - "${PHX_PORT:-4000}:4000"
    volumes:
      - .:/app
      - deps:/app/deps
      - build:/app/_build
      - node_modules:/app/assets/node_modules
    working_dir: /app
    command: >
      sh -c "
        mix deps.get &&
        mix ecto.setup &&
        mix phx.server
      "
    stdin_open: true
    tty: true
    networks:
      - conezia_network

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  minio_data:
    driver: local
  deps:
    driver: local
  build:
    driver: local
  node_modules:
    driver: local

networks:
  conezia_network:
    driver: bridge
```

### 2.2 Development Dockerfile (Dockerfile.dev)

```dockerfile
# Dockerfile.dev - Development environment
FROM elixir:1.16-otp-26-alpine

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    inotify-tools \
    postgresql-client \
    curl

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set working directory
WORKDIR /app

# Install dependencies for file watching (for live reload)
ENV ERL_AFLAGS="-kernel shell_history enabled"

# Expose Phoenix port
EXPOSE 4000

# Default command
CMD ["mix", "phx.server"]
```

### 2.3 PostgreSQL Initialization Script

```sql
-- docker/postgres/init.sql
-- Enable required extensions

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- Create test database
CREATE DATABASE conezia_test;
GRANT ALL PRIVILEGES ON DATABASE conezia_test TO conezia;
```

---

## 3. Production Environment

### 3.1 Production Dockerfile

```dockerfile
# Dockerfile - Production multi-stage build
# Stage 1: Build
FROM elixir:1.16-otp-26-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm

# Set build environment
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set working directory
WORKDIR /app

# Copy dependency files
COPY mix.exs mix.lock ./
COPY config config

# Install dependencies
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy assets and compile
COPY assets assets
COPY priv priv
COPY lib lib

# Build assets
RUN cd assets && npm ci && npm run deploy
RUN mix phx.digest

# Compile release
RUN mix compile
RUN mix release

# Stage 2: Runtime
FROM alpine:3.19 AS runner

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    ca-certificates \
    curl

# Create non-root user
RUN addgroup -g 1000 conezia && \
    adduser -u 1000 -G conezia -s /bin/sh -D conezia

# Set working directory
WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=conezia:conezia /app/_build/prod/rel/conezia ./

# Set user
USER conezia

# Environment variables
ENV HOME=/app
ENV MIX_ENV=prod
ENV PHX_SERVER=true

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Expose port
EXPOSE 4000

# Start command
CMD ["bin/conezia", "start"]
```

### 3.2 Production docker-compose.yml

```yaml
# docker-compose.prod.yml
version: "3.8"

services:
  # PostgreSQL Primary
  postgres:
    image: postgres:16-alpine
    container_name: conezia_postgres_prod
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - conezia_internal
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G

  # PostgreSQL Read Replica (optional)
  postgres-replica:
    image: postgres:16-alpine
    container_name: conezia_postgres_replica
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data
    command: >
      bash -c "
        until pg_basebackup -h postgres -U ${POSTGRES_USER} -D /var/lib/postgresql/data -Fp -Xs -P -R; do
          echo 'Waiting for primary...';
          sleep 5;
        done;
        postgres
      "
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - postgres_replica_data:/var/lib/postgresql/data
    networks:
      - conezia_internal
    profiles:
      - with-replica

  # Redis Cluster
  redis:
    image: redis:7-alpine
    container_name: conezia_redis_prod
    restart: always
    command: >
      redis-server
      --appendonly yes
      --maxmemory 1gb
      --maxmemory-policy allkeys-lru
      --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - conezia_internal
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

  # Phoenix Application
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: conezia_app_prod
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      MIX_ENV: prod
      DATABASE_URL: ecto://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      DATABASE_POOL_SIZE: ${DATABASE_POOL_SIZE:-20}
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      PHX_HOST: ${PHX_HOST}
      PHX_PORT: 4000
      S3_ENDPOINT: ${S3_ENDPOINT}
      S3_BUCKET: ${S3_BUCKET}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      AWS_REGION: ${AWS_REGION:-us-east-1}
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
      SENTRY_DSN: ${SENTRY_DSN}
    networks:
      - conezia_internal
      - conezia_external
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
      rollback_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: any
        delay: 5s
        max_attempts: 3

  # Nginx Load Balancer
  nginx:
    image: nginx:alpine
    container_name: conezia_nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./docker/nginx/ssl:/etc/nginx/ssl:ro
      - nginx_cache:/var/cache/nginx
    depends_on:
      - app
    networks:
      - conezia_external
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M

volumes:
  postgres_data:
    driver: local
  postgres_replica_data:
    driver: local
  redis_data:
    driver: local
  nginx_cache:
    driver: local

networks:
  conezia_internal:
    driver: bridge
    internal: true
  conezia_external:
    driver: bridge
```

### 3.3 Nginx Configuration

```nginx
# docker/nginx/nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript
               application/xml application/xml+rss text/javascript application/x-javascript;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;
    limit_conn_zone $binary_remote_addr zone=conn:10m;

    # Upstream Phoenix servers
    upstream phoenix {
        least_conn;
        server app:4000 weight=1 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    # HTTP to HTTPS redirect
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    # Main HTTPS server
    server {
        listen 443 ssl http2;
        server_name api.conezia.com;

        # SSL Configuration
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:50m;
        ssl_session_tickets off;

        # Modern SSL configuration
        ssl_protocols TLSv1.3 TLSv1.2;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;

        # HSTS
        add_header Strict-Transport-Security "max-age=63072000" always;

        # Client body size
        client_max_body_size 50M;

        # Health check endpoint
        location /health {
            proxy_pass http://phoenix;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            access_log off;
        }

        # API endpoints with rate limiting
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            limit_conn conn 10;

            proxy_pass http://phoenix;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "";

            proxy_connect_timeout 30s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Auth endpoints with stricter rate limiting
        location /api/v1/auth/ {
            limit_req zone=auth burst=5 nodelay;
            limit_conn conn 5;

            proxy_pass http://phoenix;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "";
        }

        # WebSocket endpoint for Phoenix Channels
        location /socket {
            proxy_pass http://phoenix;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_connect_timeout 7d;
            proxy_send_timeout 7d;
            proxy_read_timeout 7d;
        }

        # LiveView endpoint
        location /live {
            proxy_pass http://phoenix;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Static assets with caching
        location /assets {
            proxy_pass http://phoenix;
            proxy_http_version 1.1;
            proxy_set_header Host $host;

            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # Default location
        location / {
            proxy_pass http://phoenix;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "";
        }
    }
}
```

---

## 4. Environment Configuration

### 4.1 Development .env

```bash
# .env.dev - Development environment variables

# PostgreSQL
POSTGRES_USER=conezia
POSTGRES_PASSWORD=conezia_dev
POSTGRES_DB=conezia_dev
POSTGRES_PORT=5432

# Redis
REDIS_PORT=6379

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001

# MailHog
MAILHOG_SMTP_PORT=1025
MAILHOG_UI_PORT=8025

# Phoenix
PHX_PORT=4000
SECRET_KEY_BASE=dev_secret_key_base_that_is_at_least_64_bytes_long_for_development_only

# Google OAuth (use test credentials)
GOOGLE_CLIENT_ID=your-dev-client-id
GOOGLE_CLIENT_SECRET=your-dev-client-secret
```

### 4.2 Production .env Template

```bash
# .env.prod.template - Production environment variables (DO NOT COMMIT ACTUAL VALUES)

# PostgreSQL
POSTGRES_USER=conezia_prod
POSTGRES_PASSWORD=<GENERATE_SECURE_PASSWORD>
POSTGRES_DB=conezia_production
DATABASE_POOL_SIZE=20

# Redis
REDIS_PASSWORD=<GENERATE_SECURE_PASSWORD>

# Phoenix
SECRET_KEY_BASE=<GENERATE_WITH_mix_phx.gen.secret>
PHX_HOST=api.conezia.com

# AWS S3
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=conezia-production
AWS_ACCESS_KEY_ID=<YOUR_AWS_KEY>
AWS_SECRET_ACCESS_KEY=<YOUR_AWS_SECRET>
AWS_REGION=us-east-1

# SMTP
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASSWORD=<YOUR_SENDGRID_API_KEY>

# Google OAuth
GOOGLE_CLIENT_ID=<YOUR_PRODUCTION_CLIENT_ID>
GOOGLE_CLIENT_SECRET=<YOUR_PRODUCTION_CLIENT_SECRET>

# Monitoring
SENTRY_DSN=<YOUR_SENTRY_DSN>
```

---

## 5. Helper Scripts

### 5.1 Development Commands (Makefile)

```makefile
# Makefile - Development helper commands

.PHONY: help setup start stop restart logs shell db-console redis-console test lint

# Default target
help:
	@echo "Conezia Development Commands"
	@echo ""
	@echo "  make setup      - Initial setup (build and start containers)"
	@echo "  make start      - Start all services"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make logs       - View logs (all services)"
	@echo "  make logs-app   - View app logs only"
	@echo "  make shell      - Open shell in app container"
	@echo "  make iex        - Open IEx console in app container"
	@echo "  make db-console - Open PostgreSQL console"
	@echo "  make redis-cli  - Open Redis CLI"
	@echo "  make test       - Run tests"
	@echo "  make lint       - Run linters"
	@echo "  make clean      - Remove containers and volumes"

# Initial setup
setup:
	@echo "Setting up development environment..."
	cp -n .env.dev .env || true
	docker-compose build
	docker-compose up -d postgres redis minio
	@echo "Waiting for services to be healthy..."
	sleep 10
	docker-compose up -d
	@echo "Setup complete! Access the app at http://localhost:4000"

# Start services
start:
	docker-compose up -d

# Stop services
stop:
	docker-compose down

# Restart services
restart:
	docker-compose restart

# View logs
logs:
	docker-compose logs -f

logs-app:
	docker-compose logs -f app

# Shell access
shell:
	docker-compose exec app sh

iex:
	docker-compose exec app iex -S mix

# Database console
db-console:
	docker-compose exec postgres psql -U conezia -d conezia_dev

# Redis CLI
redis-cli:
	docker-compose exec redis redis-cli

# Run tests
test:
	docker-compose exec app mix test

test-watch:
	docker-compose exec app mix test.watch

# Run linters
lint:
	docker-compose exec app mix format --check-formatted
	docker-compose exec app mix credo --strict
	docker-compose exec app mix dialyzer

# Format code
format:
	docker-compose exec app mix format

# Database tasks
db-migrate:
	docker-compose exec app mix ecto.migrate

db-rollback:
	docker-compose exec app mix ecto.rollback

db-reset:
	docker-compose exec app mix ecto.reset

db-seed:
	docker-compose exec app mix run priv/repo/seeds.exs

# Clean up
clean:
	docker-compose down -v --rmi local
	rm -rf deps _build

# Production build test
build-prod:
	docker build -t conezia:latest .

# Health check
health:
	@curl -sf http://localhost:4000/health && echo "App is healthy" || echo "App is not responding"
```

### 5.2 Database Backup Script

```bash
#!/bin/bash
# docker/scripts/backup.sh - Database backup script

set -e

BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/conezia_${TIMESTAMP}.sql.gz"

# Create backup directory if not exists
mkdir -p ${BACKUP_DIR}

# Perform backup
echo "Starting database backup..."
docker-compose exec -T postgres pg_dump \
    -U ${POSTGRES_USER} \
    -d ${POSTGRES_DB} \
    --no-owner \
    --no-acl \
    | gzip > ${BACKUP_FILE}

# Remove backups older than 7 days
find ${BACKUP_DIR} -name "conezia_*.sql.gz" -mtime +7 -delete

echo "Backup completed: ${BACKUP_FILE}"
echo "Backup size: $(du -h ${BACKUP_FILE} | cut -f1)"
```

### 5.3 Health Check Script

```bash
#!/bin/bash
# docker/scripts/healthcheck.sh - Container health check

set -e

# Check PostgreSQL
pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} -h localhost

# Check if migrations are up to date
mix ecto.migrations --migrations-path priv/repo/migrations 2>&1 | grep -q "down" && exit 1

# Check Phoenix endpoint
curl -sf http://localhost:4000/health || exit 1

exit 0
```

---

## 6. Testing Environment

### 6.1 Test docker-compose Override

```yaml
# docker-compose.test.yml
version: "3.8"

services:
  postgres:
    environment:
      POSTGRES_DB: conezia_test
    tmpfs:
      - /var/lib/postgresql/data

  redis:
    command: redis-server --appendonly no
    tmpfs:
      - /data

  app:
    environment:
      MIX_ENV: test
      DATABASE_URL: ecto://conezia:conezia_dev@postgres:5432/conezia_test
    command: >
      sh -c "
        mix deps.get &&
        mix ecto.create &&
        mix ecto.migrate &&
        mix test
      "
```

### 6.2 CI/CD Test Command

```bash
# Run tests in CI
docker-compose -f docker-compose.yml -f docker-compose.test.yml up \
    --build \
    --abort-on-container-exit \
    --exit-code-from app
```

---

## 7. Monitoring & Logging

### 7.1 Logging Configuration

```elixir
# config/prod.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id],
  level: :info

# JSON logging for production
config :logger, :console,
  format: {Jason, :encode!},
  metadata: :all
```

### 7.2 Prometheus Metrics (Optional)

```yaml
# docker-compose.monitoring.yml
version: "3.8"

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: conezia_prometheus
    volumes:
      - ./docker/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - conezia_network

  grafana:
    image: grafana/grafana:latest
    container_name: conezia_grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-admin}
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"
    networks:
      - conezia_network

volumes:
  prometheus_data:
  grafana_data:
```

---

## 8. Security Considerations

### 8.1 Container Security

```yaml
# Security settings for production containers
services:
  app:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
```

### 8.2 Network Security

```yaml
# Isolated internal network
networks:
  conezia_internal:
    driver: bridge
    internal: true  # No external access
    driver_opts:
      com.docker.network.bridge.enable_ip_masquerade: "false"
```

### 8.3 Secrets Management

For production, use Docker secrets or a secrets manager:

```yaml
services:
  app:
    secrets:
      - db_password
      - secret_key_base
    environment:
      DATABASE_URL_FILE: /run/secrets/db_password

secrets:
  db_password:
    external: true
  secret_key_base:
    external: true
```

---

*Document Version: 1.0*
*Created: 2026-01-17*
