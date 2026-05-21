---
description: Directory layout and code organisation patterns (services, controllers, mappers, repositories)
---

## Key Directories

- `/src/main/java/nl/crawler/` — Application code
  - `custom/` — Custom domain logic
  - `domain/` — JPA entity classes
  - `repository/` — Data access (JPA + custom repositories)
  - `web/` — REST controllers (auto-generated from OpenAPI spec)
  - `security/` — OAuth2/Keycloak configuration
  - `config/` — Spring configuration beans
- `/src/main/resources/config/` — Application properties
  - `application.yml` — Base config
  - `application-dev.yml` — Development overrides
  - `application-prod.yml` — Production overrides
- `/src/main/resources/config/liquibase/` — Database migrations
- `/src/main/docker/` — Docker Compose configurations
- `/jdl.jdl` — JHipster entity definitions (source of truth for schema)
- `/pom.xml` — Maven dependencies and build config

## Custom Services Layer

Services live in `/src/main/java/nl/crawler/custom/service/` organised by domain:

- `customer/` — Customer management
- `tariff/` — Tariff lookups and pricing
- `invoice/` — Invoice generation and calculations
- `document/offer/` — Offer/contract PDF generation
- `job/` — Scheduled tasks (usage sync, tariff sync, invoice generation)
- `email/` — Email delivery via Microsoft Graph
- `keycloak/` — User/role management
- `s3/` — AWS S3 storage
- `edsn/`, `kvk/`, `lvbag/` — External integrations

## Controller Pattern

Controllers are in `/src/main/java/nl/crawler/custom/controller/` and implement auto-generated API interfaces from the OpenAPI spec. They delegate to services — never contain business logic.

**Example chain:** `TariffController` → `TariffService` → `TariffRepositoryCustom`

## Mapper Layer

MapStruct mappers in `/src/main/java/nl/crawler/custom/mapper/` handle entity ↔ DTO conversions. Custom mappers exist for BigDecimal and enum conversions.

## Repository Pattern

Repositories in `/src/main/java/nl/crawler/custom/repository/` extend JPA `Repository` with custom query methods. Complex queries use `*RepositoryCustomImpl` with native SQL or JPQL.
