---
description: REST API pattern, invoice/offer generation, tariff model, error handling, and logging conventions
---

## REST API Pattern

- OpenAPI spec: `src/main/resources/swagger/api.yml` — single source of truth for all endpoints
- Controllers are auto-generated via `openapi-generator-maven-plugin`; regenerate with `./mvnw generate-sources`
- Custom controllers implement the generated `*Api` interfaces and delegate to services
- Response DTOs are in `src/main/java/nl/crawler/service/api/dto/`

## Invoice & Offer Generation

- `DocumentGenerationService` — orchestrates PDF generation
- `OfferGenerationService`, `InvoiceGenerationService` — domain-specific logic
- PDF engine: LibreOffice UNO server (optional Docker service)
- Storage: AWS SDK via Garage (dev) or real S3 (prod)

## Tariff & Product Offering

- Tariffs are time-bound pricing rules with full history tracking
- Product offerings are customer-facing service packages
- `TariffService`, `ProductOfferingService` handle filtering, pagination, and history
- Dynamic tariffs are synced via a scheduled job from an external source

## Error Handling

- Custom exceptions in `/src/main/java/nl/crawler/custom/exception/`
- `ErrorMessageController` — centralised error logging entry point
- Correlation IDs are auto-injected via `CorrelationIdFilter` for end-to-end request tracing

## Logging & Tracing

- Correlation IDs: `CorrelationIdHolder` (thread-local) + `CorrelationIdFilter`
- MDC: app name injected via `ApplicationNameMdcFilter`
- Output: structured JSON via `logstash-logback-encoder` for cloud log aggregation
