---
description: Build, test, and deploy via CI/CD pipeline. Docker → GHCR → Portainer.
---

# Deploy Command

Follow Pillar 11 (CI/CD). Load `references/cicd-deployment.md` for full pipeline details.

1. Verify all tests pass (`pytest` / `npm test`)
2. Verify coverage ≥80%
3. Docker build with multi-stage, non-root USER
4. Push to GHCR with `latest` + SHA tags
5. Trivy scan for vulnerabilities
6. Deploy to Portainer stack
7. Verify health checks pass post-deploy
