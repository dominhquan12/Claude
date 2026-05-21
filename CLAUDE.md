# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

### Maven
- `./mvnw clean install` — Full build with tests
- `./mvnw spring-boot:run` — Start backend locally (requires Docker services running)
- `./mvnw verify` — Run all backend tests
- `./mvnw -ntp -Dskip.installnodenpm -Dskip.npm verify --batch-mode` — Run backend tests only (no UI)
- `./mvnw -Pprod clean verify` — Production build
- `./mvnw generate-sources` — Generate code from OpenAPI spec (`src/main/resources/swagger/api.yml`)

### Frontend/Node
- `./npmw install` — Install dependencies (runs locally managed Node/npm)
- `./npmw start` — Start webpack dev server with hot reload
- `./npmw test` — Run Jest tests
- `./npmw lint` — Run ESLint
- `./npmw lint:fix` — Auto-fix linting issues
- `./npmw run backend:start` — Start backend only (no frontend)

### Docker Services
- `docker compose -f src/main/docker/services.yml up -d` — Start PostgreSQL, Keycloak, Garage S3
- `docker compose -f src/main/docker/services.yml down` — Stop services (data preserved)
- `docker compose -f src/main/docker/services.yml down -v` — Stop and delete volumes

### Common Workflows
- **Full local stack (Option B):** Run services + local backend + local frontend
  ```bash
  docker compose -f src/main/docker/services.yml up -d
  sh src/main/docker/garage-init.sh  # one-time S3 setup
  ./mvnw spring-boot:run              # terminal 1
  cd ../crawler-frontend && pnpm dev  # terminal 2
  ```
- **Backend only:** `./mvnw spring-boot:run` (services must be running)
- **Single test:** `./mvnw verify -Dtest=YourTestClassName`

## Repository Structure

### Key Directories
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

### Code Organization

#### Custom Services Layer
Services are organized by domain in `/src/main/java/nl/crawler/custom/service/`:
- `customer/` — Customer management
- `tariff/` — Tariff lookups and pricing
- `invoice/` — Invoice generation and calculations
- `document/offer/` — Offer/contract PDF generation
- `job/` — Scheduled tasks (usage sync, tariff sync, invoice generation)
- `email/` — Email delivery via Microsoft Graph
- `keycloak/` — User/role management
- `s3/` — AWS S3 storage
- `edsn/`, `kvk/`, `lvbag/` — External integrations

#### Controller Pattern
Controllers are in `/src/main/java/nl/crawler/custom/controller/` and implement auto-generated API interfaces from OpenAPI spec. They delegate to services.

**Example:** `TariffController` → `TariffService` → `TariffRepositoryCustom`

#### Mapper Layer
MapStruct mappers in `/src/main/java/nl/crawler/custom/mapper/` handle entity ↔ DTO conversions. Custom mappers (BigDecimal, enums) handle tricky type mappings.

#### Repository Pattern
Repositories in `/src/main/java/nl/crawler/custom/repository/` extend JPA `Repository` with custom query methods. Many repositories use custom implementations (`*RepositoryCustomImpl`) for complex queries with native SQL or JPQL.

## Database & Migrations

### Liquibase Workflow
The golden rule: **never edit a committed changelog file.** Changelogs are immutable like git commits.

#### Adding/changing entities (JDL workflow)
1. Edit `jdl.jdl` — add/modify entity fields
2. Run `npx jhipster jdl jdl.jdl --force --skip-install`
3. JHipster generates new incremental changelog files (never modifies existing ones)
4. For new entities: manually add `<createSequence>` changeset as first changeset in the generated file (Hibernate requires this)
5. Review `master.xml` — JHipster adds include lines automatically
6. Commit everything

#### Manual migrations
1. Create new file: `src/main/resources/config/liquibase/changelog/TIMESTAMP_description.xml`
2. Write changeset (see LIQUIBASE.md for examples)
3. Add one line at **end** of `master.xml`: `<include file="..."/>`

#### Common fixes
- Checksum error: `docker compose ... down -v && docker compose ... up -d` (wipes and rebuilds)
- For production: add `<validCheckSum>` with old fingerprint to accept changes

See LIQUIBASE.md for full migration guide.

## Scheduled Tasks & Distributed Locking

Scheduled jobs use Spring `@Scheduled` with ShedLock for distributed locking across replicas:
- Config: `SchedulerConfiguration.java` — enables `@EnableSchedulerLock`
- Jobs located in `/src/main/java/nl/crawler/custom/service/job/`
- Lock table: `shedlock` (created automatically by Liquibase)
- Lock manager: PostgreSQL-backed JDBC

**Example:**
```java
@Scheduled(cron = "0 0 3 * * *")
@SchedulerLock(name = "myJob", lockAtMostFor = "30m", lockAtLeastFor = "5m")
public void myJob(){}
```

When running multiple replicas, only one instance executes per schedule tick. In dev (single instance), lock is immediate.

## External Services & Configuration

### Required Services (Dev)
- **PostgreSQL (app):** `localhost:5432` — User: `CrawlerBackend`
- **PostgreSQL (keycloak):** `localhost:5433` — User: `keycloak`
- **Keycloak:** `localhost:9080` — Admin: `admin`/`admin`, realm: `jhipster`
- **Garage S3:** `localhost:3900` — Access key: `GK794357f752d25d482fa8ff5d`

### External APIs (VPN/Certs Required)
- **EDSN:** Dutch energy market SOAP endpoints (15+), requires VPN + client cert
- **KVK:** Chamber of Commerce API
- **Bluem:** Bank mandate SEPA service
- **Dynamic pricing:** NieuweStroom API for gas/electricity prices
- **Microsoft Graph:** Email delivery

See DEPENDENCY-MAP.md for full details (URLs, credentials, config keys).

## Architecture Notes

### REST API Pattern
- OpenAPI spec: `src/main/resources/swagger/api.yml`
- Controllers auto-generated via openapi-generator-maven-plugin
- Controllers implement generated `*Api` interfaces and delegate to services
- Responses use DTOs defined in `src/main/java/nl/crawler/service/api/dto/`

### Invoice & Offer Generation
- `DocumentGenerationService` — orchestrates PDF generation
- `OfferGenerationService`, `InvoiceGenerationService` — domain-specific logic
- PDF generation: LibreOffice UNO server (optional Docker service)
- S3 storage: AWS SDK via Garage (dev) or real S3 (prod)

### Tariff & Product Offering
- Tariffs: time-bound pricing rules with history tracking
- Product offerings: customer-facing service packages
- Lookups: `TariffService`, `ProductOfferingService` handle filtering, pagination, and history
- Dynamic tariffs: synced via scheduled job from external source

### Error Handling
- Custom exceptions in `/src/main/java/nl/crawler/custom/exception/`
- `ErrorMessageController` — centralizes error logging
- Correlation IDs: auto-injected via `CorrelationIdFilter` for request tracing

### Logging & Tracing
- Correlation IDs: `CorrelationIdHolder` (thread-local) + `CorrelationIdFilter`
- MDC (Mapped Diagnostic Context): app name via `ApplicationNameMdcFilter`
- Logback configured with JSON output (logstash-logback-encoder) for cloud logging

## Testing

### Backend (JUnit/Maven)
- Location: `src/test/java/nl/crawler/`
- Framework: JUnit 5, Mockito
- Run all: `./mvnw verify`
- Run single: `./mvnw verify -Dtest=EanServiceTest`
- Run integration tests: `./mvnw verify -Dtest=*IntegrationTest`

### Frontend (Jest)
- Location: `src/test/javascript/`
- Run: `./npmw test`
- Watch: `./npmw test:watch`
- Update snapshots: `./npmw jest:update`

## Project Metadata

- **Build Tool:** Maven 3.2.5+
- **Java Version:** 21 (Eclipse Temurin)
- **Node:** v22.15.0 (managed by Maven frontend plugin)
- **Spring Boot:** 3.4.5 (via JHipster 8.11.0)
- **Database:** PostgreSQL 17.4
- **Authentication:** OAuth2/OpenID Connect (Keycloak)
- **Framework:** JHipster 8.11.0 with custom domain logic
- **Frontend:** React 18.3.1 (monorepo structure, see crawler-frontend)

## CI/CD

- **Pipeline:** `azure-pipelines.yml` — triggered on `dev`, `tst`, `prd`, feature branches
- **Build:** Maven clean install with caching
- **Docker:** Multi-stage Dockerfile pushed to Harbor registry
- **Deployment:** Helm charts in separate `helm-charts` repo

## Key Files to Review

- `README.md` — JHipster setup and development guides
- `DEV-README.md` — Quick-start with Option A/B/C setups
- `LIQUIBASE.md` — Database migration rules and examples
- `DEPENDENCY-MAP.md` — External services, credentials, APIs
- `.yo-rc.json` — JHipster generator configuration
- `pom.xml` — Dependencies and profiles
- `jdl.jdl` — Entity schema definitions
