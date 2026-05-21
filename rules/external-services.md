---
description: Local dev service addresses and external API integrations (EDSN, KVK, Bluem, etc.)
---

## Required Local Services (Dev)

| Service | Address | Credentials |
|---------|---------|-------------|
| PostgreSQL (app) | `localhost:5432` | User: `CrawlerBackend` |
| PostgreSQL (keycloak) | `localhost:5433` | User: `keycloak` |
| Keycloak | `localhost:9080` | `admin` / `admin`, realm: `jhipster` |
| Garage S3 | `localhost:3900` | Access key: `GK794357f752d25d482fa8ff5d` |

Start all with: `docker compose -f src/main/docker/services.yml up -d`

## External APIs (VPN + Client Certificate Required)

- **EDSN** — Dutch energy market SOAP endpoints (15+), requires VPN + client cert
- **KVK** — Chamber of Commerce API
- **Bluem** — Bank mandate / SEPA service
- **Dynamic pricing** — NieuweStroom API for gas/electricity prices
- **Microsoft Graph** — Email delivery

See `DEPENDENCY-MAP.md` for full details: URLs, credentials, and config keys.
