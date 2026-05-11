# CI/CD & Deployment Reference

Detailed guidance for Pillar 11. Read this when setting up GitHub Actions, writing Dockerfiles,
configuring docker-compose, creating Portainer stacks, or establishing deployment pipelines.

## Pipeline Architecture

```
Developer pushes to main
         │
         ├──────────────────── Security Audit (parallel) ──────────────┐
         │                     ├─ pip-audit / npm audit                │
         │                     └─ safety check                         │
         │                                                              │
         ├──────────────────── Build & Push (parallel matrix) ─────────┤
         │                     ├─ Image 1: backend/consumer             │
         │                     ├─ Image 2: backend/producer             │
         │                     └─ Image 3: frontend                     │
         │                                                              │
         └──── (after build) ── Container Scan (parallel matrix) ──────┘
                                ├─ Trivy scan per image                 │
                                └─ SARIF → GitHub Security tab          │
                                                                        │
                           Portainer watches GHCR ──── Auto/Manual Pull
                                       │
                                  Stack Update
                                       │
                                  Health Check ✅
```

## GitHub Actions Template

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_PREFIX: ghcr.io/${{ github.repository_owner }}/<project-name>

jobs:
  # ── Security Audit (runs parallel with builds) ──
  security-audit:
    name: Security Audit
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'

      - name: Install audit tools
        run: pip install pip-audit safety

      - name: pip-audit
        continue-on-error: true  # Non-blocking but visible
        run: pip-audit -r requirements.txt --desc --format markdown > audit.md || true

      - name: safety check
        continue-on-error: true
        run: safety check -r requirements.txt --full-report || true

      - name: Upload reports
        uses: actions/upload-artifact@v4
        with:
          name: security-reports
          path: audit.md
          retention-days: 30

  # ── Build & Push (parallel matrix) ──
  build-and-push:
    name: Build ${{ matrix.image }}
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    permissions:
      contents: read
      packages: write
    strategy:
      fail-fast: false  # One failure doesn't cancel others
      matrix:
        include:
          - image: backend
            dockerfile: ./Dockerfile
            context: .
          - image: frontend
            dockerfile: ./frontend/Dockerfile
            context: ./frontend
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE_PREFIX }}/${{ matrix.image }}
          tags: |
            type=raw,value=latest
            type=sha,prefix=

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ${{ matrix.context }}
          file: ${{ matrix.dockerfile }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha,scope=${{ matrix.image }}
          cache-to: type=gha,mode=max,scope=${{ matrix.image }}

  # ── Container Scan (after build) ──
  container-scan:
    name: Scan ${{ matrix.image }}
    runs-on: ubuntu-latest
    needs: build-and-push
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    permissions:
      contents: read
      packages: read
      security-events: write
    strategy:
      fail-fast: false
      matrix:
        image: [backend, frontend]
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Trivy scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.IMAGE_PREFIX }}/${{ matrix.image }}:latest
          format: 'sarif'
          output: 'trivy-${{ matrix.image }}.sarif'
          severity: 'CRITICAL,HIGH'
        continue-on-error: true

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-${{ matrix.image }}.sarif'
        continue-on-error: true
```

## Secret Scanning (MANDATORY)

Add to every CI pipeline before build:

```yaml
# GitHub Actions
- name: Secret Scan
  uses: gitleaks/gitleaks-action@v2
  with:
    config-path: .gitleaks.toml

# Container Scanning
- name: Container Security Scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: '${{ env.IMAGE_NAME }}'
    format: 'sarif'
    severity: 'CRITICAL,HIGH'
```

Minimum `.gitleaks.toml`:
```toml
[allowlist]
paths = ["*_test.go", "**/*_test.py", "*.md"]
```

## Dockerfile Patterns

### Python Backend (Production)

```dockerfile
FROM python:3.12-slim

# Prevent bytecode + enable unbuffered output
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System deps (minimal)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps FIRST (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

WORKDIR /app
COPY . /app

# Non-root user (MANDATORY)
RUN adduser -u 5678 --disabled-password --gecos "" appuser \
    && chown -R appuser /app
ENV HOME=/app
USER appuser

# Gunicorn + Uvicorn worker
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "-k", "uvicorn.workers.UvicornWorker", \
     "--timeout", "300", "--keep-alive", "5", "src.main:app"]
```

### Frontend (Multi-Stage)

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

### Key Dockerfile Rules

| Rule | Why |
|------|-----|
| Pin base image version | Reproducible builds |
| Install deps before COPY source | Layer cache optimization |
| `--no-install-recommends` | Smaller image |
| `--no-cache-dir` for pip | Smaller image |
| Non-root USER | Security (container escape mitigation) |
| Single CMD, no ENTRYPOINT override | Clear, predictable startup |
| `.dockerignore` | Exclude .git, node_modules, .env, __pycache__ |

## Docker Compose (Local Development)

```yaml
# docker-compose.yml — LOCAL development
# Build from source, hot-reload volumes, exposed ports

x-common-env: &common-env
  DATABASE_URL: ${DATABASE_URL}
  REDIS_URL: ${REDIS_URL}
  LOG_LEVEL: ${LOG_LEVEL:-DEBUG}
  ENV: development

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    environment:
      <<: *common-env
      SECRET_KEY: ${SECRET_KEY}
    ports:
      - "8000:8000"
    volumes:
      # Hot-reload: mount source for development
      - ./src:/app/src:ro
      - ./templates:/app/templates:ro
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/healthz"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped

  frontend:
    build:
      context: ./frontend
    ports:
      - "5173:80"
    depends_on:
      app:
        condition: service_healthy
    networks:
      - app-network

networks:
  app-network:
    external: true
```

### YAML Anchors for DRY Env Blocks

```yaml
# Define once at top
x-common-env: &common-env
  DATABASE_URL: ${DATABASE_URL}
  REDIS_URL: ${REDIS_URL}

# Reuse in each service
services:
  app:
    environment:
      <<: *common-env
      APP_SPECIFIC: value

  worker:
    environment:
      <<: *common-env
      WORKER_SPECIFIC: value
```

## Portainer Stack (Production)

```yaml
# portainer/stack-production.yml
# NO build context — pull pre-built images from GHCR
# Env vars injected via Portainer's Environment panel

version: "3.8"

services:
  app:
    image: ghcr.io/<org>/<project>/backend:latest
    pull_policy: always  # MANDATORY — see "Deployment Recovery Policy" below
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: ${DATABASE_URL}
      REDIS_URL: ${REDIS_URL}
      SECRET_KEY: ${SECRET_KEY}
      ENV: production
      LOG_LEVEL: INFO
    volumes:
      - app-logs:/app/logs
    networks:
      - app-network
    restart: unless-stopped

  frontend:
    image: ghcr.io/<org>/<project>/frontend:latest
    pull_policy: always  # MANDATORY — see "Deployment Recovery Policy" below
    ports:
      - "80:80"
    networks:
      - app-network
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
      resources:
        limits:
          memory: 256M

volumes:
  app-logs:
    driver: local

networks:
  app-network:
    external: true
```

### Local vs Production Summary

Local: `build:` from source, hot-reload volumes, `.env` file, DEBUG, dev ports.
Production: `image:` from GHCR, persistent data only, Portainer env, INFO, `external: true` network, resource limits, **`pull_policy: always`**.

## Deployment Recovery Policy (MANDATORY)

**All deploys flow through Portainer. Never `docker pull ghcr.io/...` manually on the host.**

### Why

Manual `gh auth token | ssh <host> 'docker login ghcr.io -u <user> --password-stdin' && ssh <host> 'docker pull <image>:latest'` solves "stale image after redeploy webhook" mechanically — but it's an **anti-pattern** for three reasons:

1. **Security.** Persists a long-lived GHCR token in `~/.docker/config.json` on the host. The credential lives outside Portainer's secret management, doesn't rotate with stack updates, and survives container redeploys.
2. **Auditability.** Bypasses Portainer's stack-state log. The "deploy" doesn't appear in Stacks history — only the underlying container restart does, with no association to a tag/digest change.
3. **Consistency.** Creates a second deploy path that can diverge from the canonical one. Future Portainer redeploys may overwrite the manually-pulled state with whatever the stack's image reference resolves to at that moment.

### The canonical Portainer-native recovery routes

When a redeploy webhook restarted containers but didn't pull (`StartedAt` advanced, image SHA unchanged), use one of these — in order of speed:

```bash
# 1. Portainer UI (fastest, always works on CE + BE)
#    Stacks → <stack_name> → Editor → check "Re-pull image and redeploy" → Update
#    ~10 seconds. Fully audited inside Portainer.

# 2. Stack webhook with pullImage=true (Portainer BE supports this)
curl -sS -X POST "$PORTAINER_WEBHOOK_URL?pullImage=true"

# 3. Re-fire the CI/CD redeploy job (when Portainer's webhook is misconfigured)
gh api -X POST /repos/<owner>/<repo>/actions/jobs/<redeploy_job_id>/rerun
```

### Permanent fix

Add `pull_policy: always` to every service in `portainer/stack-*.yml` (shown in the example above). Compose's `up -d` then re-pulls the `:latest` tag on every redeploy, regardless of whether the webhook explicitly requested it. **This is the cleanest cross-edition (CE+BE) solution** — it doesn't depend on which Portainer features your edition has.

Alternative for Portainer BE users: configure each stack's webhook to "Pull image on webhook trigger" in the UI. Removes the need for `pull_policy: always` but requires Portainer BE.

### Acceptable use of `gh auth | ssh docker login` (DIAGNOSTIC ONLY)

You may use the manual-pull path **once** to confirm reachability when debugging — e.g. "is the new image even visible from this host?" — but always:

1. Run `docker logout ghcr.io` immediately after. Never leave credentials behind.
2. Recover the actual deploy via one of the three Portainer-native routes above.
3. File a follow-up issue to add `pull_policy: always` to the stack file so this trap doesn't recur.

### Anti-patterns

- ❌ `gh auth token | ssh <host> 'docker login ghcr.io -u <user> --password-stdin'` as a routine deploy step.
- ❌ Wiring a "manual pull" step into `redeploy.yml` GitHub Action.
- ❌ Leaving `~/.docker/config.json` with GHCR creds on production hosts.
- ❌ Pulling manually then restarting the container via `docker run` (bypasses stack mgmt entirely; next Portainer redeploy will overwrite).

## Environment Variable Propagation

The complete chain that must stay synchronized:

```
.env.example          → Documentation (committed, empty values)
.env                  → Local values (gitignored)
docker-compose.yml    → ${VAR} references (reads .env)
portainer/stack-*.yml → ${VAR} references (reads Portainer env)
src/config.py         → Pydantic model with Field() validation
CI/CD secrets         → GitHub Secrets / repository variables
```

**When adding a new env var, touch ALL files in this chain.**

## Celery Worker Deployment Pattern

```yaml
# Worker with --purge for clean slate after deployment
celery_worker:
  image: ghcr.io/<org>/<project>/backend:latest
  command: celery -A src.celery_app worker --loglevel=info --concurrency=2 --purge
  environment:
    <<: *common-env
  depends_on:
    - app
  restart: unless-stopped

# Beat scheduler with RedBeat (Redis-backed, distributed lock)
celery_beat:
  image: ghcr.io/<org>/<project>/backend:latest
  command: celery -A src.celery_app beat --scheduler redbeat.RedBeatScheduler --loglevel=info
  depends_on:
    - celery_worker
  restart: unless-stopped
```

## Health Check Patterns

```yaml
# HTTP health check (FastAPI/Express)
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8000/healthz"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s  # Grace period for slow-starting apps

# Python-based (no curl needed)
healthcheck:
  test: ["CMD", "python", "-c",
         "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s
```

## .dockerignore Template

```
.git
.github
.venv
__pycache__
*.pyc
node_modules
.env
.env.*
!.env.example
*.md
docs/
tests/
.claude/
.cursor/
.vscode/
logs/
*.log
```

## Deployment Checklist

Before deploying to production:

- [ ] CI pipeline passes (security audit + build + container scan)
- [ ] All images tagged with `latest` + `sha-<commit>`
- [ ] `.env.example` documents every env var used
- [ ] Portainer stack env vars match `.env.example`
- [ ] Health checks configured for all services
- [ ] Non-root user in all Dockerfiles
- [ ] `.dockerignore` excludes sensitive/unnecessary files
- [ ] Secrets are NOT in any committed file
- [ ] Resource limits set in production stack
- [ ] Restart policies configured
- [ ] Logs persisted via named volumes
- [ ] External network created and referenced