---
description: Maven, frontend, and Docker build/run commands for local development
---

## Maven

- `./mvnw clean install` — Full build with tests
- `./mvnw spring-boot:run` — Start backend locally (requires Docker services running)
- `./mvnw verify` — Run all backend tests
- `./mvnw -ntp -Dskip.installnodenpm -Dskip.npm verify --batch-mode` — Run backend tests only (no UI)
- `./mvnw -Pprod clean verify` — Production build
- `./mvnw generate-sources` — Generate code from OpenAPI spec (`src/main/resources/swagger/api.yml`)
- `./mvnw verify -Dtest=YourTestClassName` — Run a single test class

## Frontend / Node

- `./npmw install` — Install dependencies (runs locally managed Node/npm)
- `./npmw start` — Start webpack dev server with hot reload
- `./npmw test` — Run Jest tests
- `./npmw lint` — Run ESLint
- `./npmw lint:fix` — Auto-fix linting issues
- `./npmw run backend:start` — Start backend only (no frontend)

## Docker Services

- `docker compose -f src/main/docker/services.yml up -d` — Start PostgreSQL, Keycloak, Garage S3
- `docker compose -f src/main/docker/services.yml down` — Stop services (data preserved)
- `docker compose -f src/main/docker/services.yml down -v` — Stop and delete volumes

## Common Workflows

**Full local stack:**
```bash
docker compose -f src/main/docker/services.yml up -d
sh src/main/docker/garage-init.sh  # one-time S3 setup
./mvnw spring-boot:run              # terminal 1
cd ../crawler-frontend && pnpm dev  # terminal 2
```

**Backend only:** `./mvnw spring-boot:run` (services must be running first)
