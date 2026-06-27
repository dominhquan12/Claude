# Timezone Best Practices (Java Backend - Energy/Billing Systems)

## Core Principles

### 1. Technical Timestamp vs Business Date

There are two fundamentally different kinds of date/time values.

#### Technical Timestamp

Represents **an exact moment in time**.

Examples:

- created_at
- updated_at
- deleted_at
- event_time
- kafka_event_time
- published_at

Use:

```java
Instant
```

Store as **UTC**.

Example:

```
2026-01-14T17:30:00Z
```

---

#### Business Date

Represents **a business calendar date**, not a specific moment.

Examples:

- contract_start_date
- billing_date
- due_date
- cooling_off_end_date
- move_in_date
- move_out_date

Use:

```java
LocalDate
```

Store only the date.

Example:

```
2026-01-15
```

Never convert business dates using timezone.

---

# Server Timezone vs Business Timezone

Never use the server timezone for business logic.

Bad:

```java
LocalDate.now()
```

because it depends on:

```
ZoneId.systemDefault()
```

Correct:

```java
LocalDate.now(
    ZoneId.of("Europe/Amsterdam")
)
```

Business rules should always use the market timezone.

---

# Market Timezone

Business rules follow the market where electricity is supplied, not:

- developer location
- customer location
- server location

Example:

```
Customer: Vietnam
Server: AWS Singapore
Backend: Germany
Electricity Market: Netherlands
```

Business timezone:

```
Europe/Amsterdam
```

Always.

---

# DST (Daylight Saving Time)

Netherlands uses:

- **CET** (UTC+1) in winter
- **CEST** (UTC+2) in summer

Billing period boundaries can be affected during DST transitions.

**Rule:** Always use the named timezone ID — never hardcode a UTC offset.

Bad:

```java
ZoneOffset.of("+01:00") // wrong in summer (CEST = +02:00)
```

Correct:

```java
ZoneId.of("Europe/Amsterdam") // handles DST automatically
```

---

# Timezone Constant

Avoid magic strings. Define a single constant:

```java
public final class BusinessConstants {
    public static final ZoneId MARKET_TIMEZONE = ZoneId.of("Europe/Amsterdam");
}
```

Usage:

```java
LocalDate.now(BusinessConstants.MARKET_TIMEZONE)
```

---

# Clock Injection (Testability)

Instead of calling `LocalDate.now(ZoneId...)` directly in service code, inject a `Clock` bean so tests can mock time. This is critical for billing jobs.

**Config:**

```java
@Configuration
public class ClockConfig {

    @Bean
    public Clock clock() {
        return Clock.system(BusinessConstants.MARKET_TIMEZONE);
    }
}
```

**Service:**

```java
@Service
@RequiredArgsConstructor
public class BillingServiceImpl implements BillingService {

    private final Clock clock;

    public void generateInvoice() {
        LocalDate today = LocalDate.now(clock);
        // ...
    }
}
```

**Test:**

```java
Clock fixedClock = Clock.fixed(
    Instant.parse("2026-01-14T17:30:00Z"),
    BusinessConstants.MARKET_TIMEZONE
);
// inject fixedClock into service
```

---

# Example

Customer signs contract:

```
Vietnam:
2026-01-15 00:30
```

Actual instant:

```
UTC:
2026-01-14T17:30:00Z
```

Amsterdam:

```
2026-01-14 18:30
```

Result:

```
createdAt = 2026-01-14T17:30:00Z
contractSignedDate = 2026-01-14
```

Notice:

Although Vietnam is already Jan 15,
business date is still Jan 14 because the market is Netherlands.

---

# API Design

## Technical Timestamp

Backend returns UTC.

```json
{
  "createdAt": "2026-01-14T17:30:00Z"
}
```

Frontend converts to user's local timezone.

---

## Business Date

Backend returns only date.

```json
{
  "contractStartDate": "2026-01-15",
  "billingDate": "2026-02-15"
}
```

Frontend must NOT convert timezone.

Simply display:

```
15/01/2026
```

---

# Java Types

## Instant

Represents one exact point in time.

Good for:

- audit
- logs
- kafka
- events
- created_at
- updated_at

---

## LocalDate

Represents only a calendar date.

Good for:

- invoice date
- due date
- contract start date
- billing day
- move in date

---

## OffsetDateTime

Contains:

- date
- time
- UTC offset

Example:

```
2026-01-15T10:30:00+01:00
```

Usually used when consuming external APIs.

Often converted to:

```java
Instant
```

before storing.

---

## ZonedDateTime

Contains:

- date
- time
- timezone ID

Example:

```
2026-01-15T10:30:00+01:00[Europe/Amsterdam]
```

Useful for display or timezone-specific calculations.

---

# Database Recommendation

Use:

```
Instant
```

for:

- created_at
- updated_at
- event_time

Use:

```
LocalDate
```

for:

- contract_start_date
- billing_date
- due_date
- cooling_off_end_date

---

# Spring Boot / JPA Configuration

## application.yml

```yaml
spring:
  jackson:
    time-zone: UTC
    serialization:
      write-dates-as-timestamps: false
```

## JPA Column Mapping (Hibernate 6)

| Java Type | DB Column Type | Liquibase |
|-----------|---------------|-----------|
| `Instant` | `TIMESTAMP` | `type="TIMESTAMP"` |
| `LocalDate` | `DATE` | `type="DATE"` |

> Hibernate 6 automatically stores `Instant` in UTC. No extra annotation needed.

---

# Frontend Rules

## Timestamp

Backend:

```json
{
  "createdAt": "2026-01-14T17:30:00Z"
}
```

Frontend:

- detect browser timezone
- convert automatically

User in Vietnam:

```
15/01/2026 00:30
```

User in London:

```
14/01/2026 17:30
```

---

## Business Date

Backend:

```json
{
  "contractStartDate": "2026-01-15"
}
```

Frontend:

Do NOT convert.

Display exactly:

```
15/01/2026
```

---

# EDSN Integration

Do not assume every EDSN field is UTC.

Follow the API specification.

Typical mapping:

Business dates:

```
MoveInDate
MoveOutDate
SupplyStartDate
BillingDate
```

↓

```java
LocalDate
```

Event timestamps:

```
ReceivedTime
CreatedTime
UpdatedTime
```

↓

```java
OffsetDateTime
```

↓

Convert to:

```java
Instant
```

before storing.

---

# Dutch Energy Market — Specific Rules

## Gap 1: DSMR / P4 Timestamps Are Local Amsterdam Time

DSMR P1 telegrams and P4 messages from EDSN use **local Amsterdam time (CET/CEST)** — there is no timezone info in the payload.

When ingesting meter data, you must assume `Europe/Amsterdam` and convert to `Instant` explicitly.

**Bad:**
```java
Instant.parse(dsmrTimestamp) // fails — no timezone info in DSMR string
```

**Correct:**
```java
LocalDateTime localDt = LocalDateTime.parse(dsmrTimestamp, DSMR_FORMATTER);
Instant instant = localDt.atZone(BusinessConstants.MARKET_TIMEZONE).toInstant();
```

> Always apply this conversion at the EDSN/P4 integration boundary — never pass raw DSMR timestamps deeper into the system.

---

## Gap 2: DST in Hourly Time-Series Aggregation

When aggregating hourly consumption records to calculate EB tiers, do not assume every day has 24 hours.

- **Spring forward** (last Sunday of March): that day has **23 hours**
- **Fall back** (last Sunday of October): that day has **25 hours**

**Wrong approach — assumes 24h per day:**
```java
long totalHours = ChronoUnit.HOURS.between(startInstant, endInstant);
// incorrect on DST transition days
```

**Correct approach — count actual consumption records:**
```java
// Sum the actual hourly records stored in the time-series DB
// Do not derive consumption from duration arithmetic
double totalKwh = consumptionRepository.sumByEanAndPeriod(ean, startDate, endDate);
```

> Store each hourly record with its own `period_start` (Instant) and `period_end` (Instant). Aggregate by summing records — not by multiplying hours × average rate.

---

## Gap 3: Ambiguous Timestamp During DST Fall-Back

On the last Sunday of October, the clock moves from `03:00 CEST → 02:00 CET`.
The local time `02:30` occurs **twice** that day — once in CEST (+02:00) and once in CET (+01:00).

A raw string `"2026-10-25T02:30"` without offset is ambiguous.

**Resolution strategy:**

When parsing DSMR/EDSN timestamps that may fall in the ambiguous window, use `OffsetDateTime` (which preserves the offset) rather than `LocalDateTime`:

```java
// If EDSN provides offset — use it directly
OffsetDateTime odt = OffsetDateTime.parse("2026-10-25T02:30:00+02:00");
Instant instant = odt.toInstant();
```

If the source provides no offset (raw DSMR local time), apply `EARLIER` overlap resolver:

```java
LocalDateTime localDt = LocalDateTime.parse(raw, DSMR_FORMATTER);
ZonedDateTime zdt = localDt.atZone(BusinessConstants.MARKET_TIMEZONE)
    .withEarlierOffsetAtOverlap(); // prefer CEST (+02:00) if ambiguous
Instant instant = zdt.toInstant();
```

> Document which strategy is used in the integration layer. Consistency matters — mixing strategies causes duplicate or missing consumption records.

---

## Gap 4: Pro-Rata Calculation — Use LocalDate, Not Duration

When a contract starts mid-month or ends early (early termination, supplier switch), pro-rata billing is based on **calendar days** — not elapsed seconds.

**Wrong — affected by DST (23h/25h days):**
```java
long days = Duration.between(startInstant, endInstant).toDays();
// gives 364 instead of 365 on spring-forward year
```

**Correct:**
```java
long days = startDate.until(endDate, ChronoUnit.DAYS);
// pure calendar arithmetic — DST-safe
```

**Pro-rata amount:**
```java
BigDecimal proRataAmount = annualAmount
    .multiply(BigDecimal.valueOf(days))
    .divide(BigDecimal.valueOf(startDate.lengthOfYear()), 10, RoundingMode.HALF_UP);
```

> All pro-rata calculations in Eindafrekening, early termination fee, and grid fee (Captar daily rate) must use `LocalDate` arithmetic.

---

## Gap 5: "Annual" Period for EB Tier Calculation = Calendar Year

Energiebelasting (EB) tiers are calculated on **calendar year** consumption (Jan 1 – Dec 31), not contract year.

**Implication for Eindafrekening:**

When a contract ends mid-year (early termination), the EB tier must be calculated based on actual consumption **from Jan 1 to termination date** — not the full contract year.

```
Contract: 2026-03-01 → 2026-09-15 (early termination)

EB tier basis:
  period = 2026-01-01 → 2026-09-15
  total_kwh = sum of all consumption in that period at this EAN
  → apply tiered EB rates on total_kwh
```

**Tier boundary reference (electricity):**

| Tier | Range | Rate |
|------|-------|------|
| 1 | 0 – 2.900 kWh | highest |
| 2 | 2.901 – 10.000 kWh | ↓ |
| 3 | 10.001 – 50.000 kWh | ↓ |
| 4 | 50.001 – 10.000.000 kWh | lowest |

> EB rates change annually by government decision — must be **versioned** with `effective_from` / `effective_to`. Never hardcode EB rates.

**Consumption spanning a year boundary (multi-year contract):**

```
Contract: 2025-06-01 → 2027-05-31

Eindafrekening splits by calendar year:
  Period 1: 2025-06-01 → 2025-12-31  → EB tiers 2025 rates
  Period 2: 2026-01-01 → 2026-12-31  → EB tiers 2026 rates
  Period 3: 2027-01-01 → 2027-05-31  → EB tiers 2027 rates
```

---

# Golden Rules

1. Store timestamps in UTC (`Instant`).
2. Store business dates as `LocalDate`.
3. Never use server timezone for business logic.
4. Business logic always uses the market timezone (`Europe/Amsterdam`).
5. Never hardcode UTC offset (`+01:00`) — use named timezone ID to handle DST.
6. Define `MARKET_TIMEZONE` as a constant — no magic strings.
7. Inject `Clock` bean — never call `LocalDate.now(ZoneId...)` directly in service code.
8. Frontend converts only timestamps — never business dates.
9. `OffsetDateTime` is used at API boundaries — convert to `Instant` before storing.
10. `Instant` is the preferred storage type.
11. DSMR/P4 timestamps are local Amsterdam time — always convert explicitly at the integration boundary.
12. Never aggregate consumption by duration arithmetic — sum actual time-series records.
13. Ambiguous DST timestamps must have a documented resolution strategy (prefer `EARLIER` offset).
14. Pro-rata calculations always use `LocalDate.until(endDate, ChronoUnit.DAYS)` — never `Duration`.
15. EB tier calculation uses calendar year (Jan 1 – Dec 31) — split by year for multi-year contracts.
