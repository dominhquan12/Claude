# Timezone Golden Rules

Full reference: `.claude/tasks/timezone.md`

---

## Core

1. Store timestamps as `Instant` (UTC).
2. Store business dates as `LocalDate` — never convert with timezone.
3. Never use `LocalDate.now()` — always pass a `Clock` or `ZoneId`.
4. Never use server timezone for business logic.
5. Business logic always uses `Europe/Amsterdam` — defined as `BusinessConstants.MARKET_TIMEZONE`.
6. Never hardcode `+01:00` — use named timezone ID to handle DST automatically.

---

## Code Patterns

7. Inject `Clock` bean — never call `LocalDate.now(ZoneId...)` directly in service code.
8. `OffsetDateTime` at API boundaries — convert to `Instant` before storing.
9. Pro-rata calculations: use `LocalDate.until(endDate, ChronoUnit.DAYS)` — never `Duration.toDays()`.

---

## Dutch Energy Market Specific

10. DSMR/P4 timestamps from EDSN are **local Amsterdam time** — convert explicitly at the integration boundary.
11. Never aggregate consumption by duration arithmetic — sum actual time-series records (DST days have 23h or 25h).
12. Ambiguous DST timestamps (fall-back): use `withEarlierOffsetAtOverlap()` and document the strategy.
13. EB tier calculation uses **calendar year** (Jan 1 – Dec 31) — split by year for multi-year contracts.
14. EB rates change annually — must be versioned with `effective_from` / `effective_to`. Never hardcode.
