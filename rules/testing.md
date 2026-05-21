---
description: How to run and write backend (JUnit) and frontend (Jest) tests
---

## Backend Tests (JUnit 5 / Maven)

- **Location:** `src/test/java/nl/crawler/`
- **Framework:** JUnit 5, Mockito
- Run all: `./mvnw verify`
- Run single class: `./mvnw verify -Dtest=EanServiceTest`
- Run integration tests: `./mvnw verify -Dtest=*IntegrationTest`
- Run without UI build: `./mvnw -ntp -Dskip.installnodenpm -Dskip.npm verify --batch-mode`

## Frontend Tests (Jest)

- **Location:** `src/test/javascript/`
- Run: `./npmw test`
- Watch mode: `./npmw test:watch`
- Update snapshots: `./npmw jest:update`
