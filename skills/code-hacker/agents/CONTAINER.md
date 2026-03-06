# 🐳 CONTAINER — Container & Infrastructure Security

## Mission
Find container escapes, privilege escalation, and infrastructure misconfigurations.

## Detection
```bash
find . -name "Dockerfile*" -o -name "docker-compose*" -o -name "*.yaml" -o -name "*.yml" \
  | xargs grep -l "image:\|FROM\|apiVersion:" 2>/dev/null
```

## Dockerfile Checklist
```bash
rg -n "FROM.*:latest|FROM.*:master" -g "Dockerfile*"  # Unpinned base image
rg -n "USER root|--privileged" -g "Dockerfile*" -g "*.yml" -g "*.yaml"
rg -n "COPY.*\.\s+\." -g "Dockerfile*"  # Copying everything (secrets?)
rg -n "ENV.*PASSWORD|ENV.*SECRET|ENV.*KEY" -g "Dockerfile*"
rg -n "EXPOSE.*22\b" -g "Dockerfile*"  # SSH in container
```
- [ ] Running as root (must have USER non-root)
- [ ] Unpinned base image tags (:latest)
- [ ] Secrets in build args or ENV
- [ ] Unnecessary packages installed
- [ ] .dockerignore missing (copies .git, .env, node_modules)
- [ ] Multi-stage build not used (build tools in production image)

## Docker Compose Checklist
```bash
rg -n "privileged.*true|cap_add|network_mode.*host" -g "docker-compose*"
rg -n "/var/run/docker\.sock" -g "docker-compose*"  # Docker socket mount = escape
rg -n "ports:.*0\.0\.0\.0|ports:.*:" -g "docker-compose*"  # Exposed ports
```
- [ ] Privileged mode containers
- [ ] Docker socket mounted (container escape)
- [ ] Host network mode
- [ ] Unnecessary capabilities (CAP_SYS_ADMIN)
- [ ] Ports bound to 0.0.0.0 instead of 127.0.0.1

## Kubernetes Checklist
```bash
rg -n "privileged.*true|hostNetwork.*true|hostPID.*true" -g "*.yaml" -g "*.yml"
rg -n "runAsUser.*0|allowPrivilegeEscalation.*true" -g "*.yaml"
rg -n "kind: ClusterRoleBinding.*subjects.*kind: ServiceAccount" -g "*.yaml"
```
- [ ] Pods running as root
- [ ] No resource limits (CPU/memory)
- [ ] Default service account with cluster-admin
- [ ] Secrets in plain ConfigMaps instead of Secrets
- [ ] No NetworkPolicy (all pods can talk to all pods)
- [ ] No PodSecurityPolicy/Standards
