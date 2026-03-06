# 🔍 RECON — Attack Surface Mapping

## Mission
Map every entry point, technology, exposed service, and potential attack vector.

## Checklist

### 1. Technology Fingerprinting
- [ ] Identify all languages (file extensions, shebangs, imports)
- [ ] Identify frameworks (Django, Flask, Express, Spring, Rails, etc.)
- [ ] Identify databases (connection strings, ORM configs, migration files)
- [ ] Identify message queues (RabbitMQ, Kafka, Redis pub/sub)
- [ ] Identify cloud providers (AWS SDK, GCP libs, Azure configs)
- [ ] Identify container orchestration (Dockerfile, docker-compose, k8s manifests)

### 2. Entry Point Enumeration
```bash
# HTTP routes/endpoints
rg -n "@app\.(get|post|put|delete|patch|route)|@router\." --type py
rg -n "app\.(get|post|put|delete|patch|use)\(" --type js --type ts
rg -n "@(Get|Post|Put|Delete|Patch)Mapping|@RequestMapping" --type java
rg -n "(get|post|put|delete|patch)\s+['\"/]" --type rb

# GraphQL schemas
rg -n "type Query|type Mutation|type Subscription" -g "*.graphql" -g "*.gql"

# WebSocket endpoints
rg -n "WebSocket|ws://|wss://|socket\.io|@OnMessage"

# gRPC services
rg -n "service\s+\w+\s*{" -g "*.proto"

# Cron jobs / scheduled tasks
rg -n "@scheduled|crontab|celery.*task|APScheduler"

# CLI entry points
rg -n "argparse|click\.command|typer\.command|cobra\.Command"
```

### 3. Authentication Boundaries
- [ ] Which endpoints require auth? Which don't? (Map the gap)
- [ ] Are there admin endpoints? How are they protected?
- [ ] Are there internal-only endpoints exposed publicly?
- [ ] What auth mechanisms? (JWT, session, API key, OAuth, basic)

### 4. Data Flow Mapping
- [ ] Where does user input enter? (HTTP, WebSocket, CLI, file upload, message queue)
- [ ] Where does it get stored? (DB, cache, file system, cloud storage)
- [ ] Where does it get rendered? (HTML, email, PDF, logs)
- [ ] Where does it exit? (API responses, webhooks, exports)

### 5. Infrastructure Files
```bash
find . -name "Dockerfile*" -o -name "docker-compose*" -o -name ".env*" \
  -o -name "*.yaml" -o -name "*.yml" | grep -v node_modules | head -30
find . -name "nginx.conf" -o -name "apache*.conf" -o -name "Caddyfile"
find . -name "terraform*" -o -name "*.tf" -o -name "cloudformation*"
```
