---
description: Technology stack versions, CI/CD pipeline, and key reference files for this project
---

## Technology Stack

| Component | Version / Detail |
|-----------|-----------------|
| Build tool | Maven 3.2.5+ |
| Java | 21 (Eclipse Temurin) |
| Node | v22.15.0 (managed by Maven frontend plugin) |
| Spring Boot | 3.4.5 (via JHipster 8.11.0) |
| Database | PostgreSQL 17.4 |
| Authentication | OAuth2/OpenID Connect (Keycloak) |
| Framework | JHipster 8.11.0 with custom domain logic |
| Frontend | React 18.3.1 (separate `crawler-frontend` repo) |

## CI/CD

- **Pipeline:** `azure-pipelines.yml` — triggered on `dev`, `tst`, `prd`, and feature branches
- **Build:** Maven clean install with dependency caching
- **Docker:** Multi-stage Dockerfile pushed to Harbor registry
- **Deployment:** Helm charts in the separate `helm-charts` repo

## Key Reference Files

| File | Purpose |
|------|---------|
| `README.md` | JHipster setup and development guides |
| `DEV-README.md` | Quick-start guide (Option A/B/C setups) |
| `LIQUIBASE.md` | Database migration rules and examples |
| `DEPENDENCY-MAP.md` | External services, credentials, API config keys |
| `.yo-rc.json` | JHipster generator configuration |
| `pom.xml` | Maven dependencies and build profiles |
| `jdl.jdl` | Entity schema definitions (source of truth) |
