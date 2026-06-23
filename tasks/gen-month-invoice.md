# Monthly Advance Billing Rules

## Overview

The system generates invoices on the **15th day of each month**.

Billing model:

* Advance Billing
* Billing Period = Calendar Month
* Billing Run Day = 15

Example:

| Invoice Generation Date | Billing Period  |
| ----------------------- | --------------- |
| 15 Jan                  | 01 Feb - 28 Feb |
| 15 Feb                  | 01 Mar - 31 Mar |
| 15 Mar                  | 01 Apr - 30 Apr |

---

# First Invoice Rules

The first invoice depends on the Supply Start Date.

## Scenario 1: Supply Start Date on or before Billing Day (<= 15)

### Example

Supply Start Date:

```text
01 Jan
```

### Invoice Timeline

| Invoice Type    | Generated Date | Billing Period  |
| --------------- | -------------- | --------------- |
| Initial Invoice | 01 Jan         | 01 Jan - 31 Jan |
| Regular Invoice | 15 Jan         | 01 Feb - 28 Feb |
| Regular Invoice | 15 Feb         | 01 Mar - 31 Mar |

### Another Example

Supply Start Date:

```text
10 Jan
```

| Invoice Type    | Generated Date | Billing Period  |
| --------------- | -------------- | --------------- |
| Initial Invoice | 10 Jan         | 10 Jan - 31 Jan |
| Regular Invoice | 15 Jan         | 01 Feb - 28 Feb |
| Regular Invoice | 15 Feb         | 01 Mar - 31 Mar |

### Business Rule

If:

```text
Supply Start Date <= Billing Day
```

Then:

```text
Initial Invoice
=
Supply Start Date
to
End Of Current Month
```

After that:

```text
Regular Billing Cycle starts on the next billing run.
```

---

# Scenario 2: Supply Start Date after Billing Day (> 15)

### Example

Supply Start Date:

```text
20 Jan
```

### Invoice Timeline

| Invoice Type    | Generated Date | Billing Period  |
| --------------- | -------------- | --------------- |
| Initial Invoice | 20 Jan         | 20 Jan - 31 Jan |
| Advance Invoice | 20 Jan         | 01 Feb - 28 Feb |
| Regular Invoice | 15 Feb         | 01 Mar - 31 Mar |
| Regular Invoice | 15 Mar         | 01 Apr - 30 Apr |

### Another Example

Supply Start Date:

```text
31 Jan
```

| Invoice Type    | Generated Date | Billing Period  |
| --------------- | -------------- | --------------- |
| Initial Invoice | 31 Jan         | 31 Jan - 31 Jan |
| Advance Invoice | 31 Jan         | 01 Feb - 28 Feb |
| Regular Invoice | 15 Feb         | 01 Mar - 31 Mar |

### Business Rule

If:

```text
Supply Start Date > Billing Day
```

Then generate:

#### Invoice 1

```text
Supply Start Date
to
End Of Current Month
```

#### Invoice 2

```text
First Day Of Next Month
to
End Of Next Month
```

Both invoices are generated immediately when the supply becomes active.

After that:

```text
Regular Billing Cycle starts on the next billing run.
```

---

# Summary

## Supply Start Date <= 15

Generate:

```text
Initial Invoice
=
Supply Start Date -> End Of Current Month
```

Then wait for:

```text
15th Billing Run
```

to generate the next month's invoice.

---

## Supply Start Date > 15

Generate immediately:

```text
Invoice #1
=
Supply Start Date -> End Of Current Month
```

and

```text
Invoice #2
=
First Day Of Next Month -> End Of Next Month
```

This ensures there is no missing billing period before the next regular billing cycle.

---

# Invoice Generation Jobs & Tools

## Purpose of Each API

| API | Purpose |
| --- | ------- |
| `generateMonthInvoice` | Generate initial invoice(s) at supply start (onboarding) |
| `generateInvoicesOfYear` | Backfill missing invoices for a specific customer and year |
| `generateInvoicesWithCustomDate` | Backfill missing invoices for all agreements up to a given date |
| `runMonthlyBillingJob` | Regular 15th job — generate next month's invoice only |

---

## Monthly Billing Job (`runMonthlyBillingJob`)

**Purpose:** Generate the advance invoice for the next month. Runs on the 15th.

**Rule:**
- Input: `runDate` (the 15th of a month)
- Generates exactly **1 invoice** per agreement: the invoice for `runDate + 1 month`
- Does **not** backfill gaps — if a past invoice is missing, use Generate All instead
- Idempotent: if the invoice already exists, skip

```
runDate = 15/06/2026
→ generates invoice for: 01/07/2026 – 31/07/2026
```

| API | targetEnd | jobDate |
| --- | --------- | ------- |
| `runMonthlyBillingJob` | firstDay(runDate + 1 month) to lastDay | runDate |

---

## Generate All Monthly (`generateInvoicesWithCustomDate`)

**Purpose:** Manual repair tool — backfill all missing invoices for all active agreements.
Use when the job failed, or initial invoices were not created.

**Rule:**
- Input: `invoiceDate`
- `targetEnd = invoiceDate + 1 month (last day)`
- Scans from `agreement.effectiveDate` to `targetEnd`
- Creates any missing invoice in that range (skips existing ones)
- Includes next month to cover cases where the job failed for that cycle

```
invoiceDate = 17/07/2024
→ targetEnd = 31/08/2024
→ backfills all missing months from effectiveDate to August
```

| API | targetEnd | jobDate |
| --- | --------- | ------- |
| `generateInvoicesWithCustomDate` | lastDay(invoiceDate + 1 month) | invoiceDate |

---

## Generate By ID (`generateInvoicesOfYear`)

**Purpose:** Manual repair tool for a specific customer — backfill all missing invoices for a given year.

**Rule:**
- Input: `customerId`, `year`
- If `today < yearEnd`: `targetEnd = min(today + 1 month last day, yearEnd)`
- If `today >= yearEnd`: `targetEnd = yearEnd (31 Dec)`
- Scans from `agreement.effectiveDate` to `targetEnd`
- Creates any missing invoice in that range (skips existing ones)

```
year = 2026, today = 23/06/2026
→ targetEnd = 31/07/2026
→ backfills all missing months from effectiveDate to July 2026
```

| API | targetEnd | jobDate |
| --- | --------- | ------- |
| `generateInvoicesOfYear` (current year) | min(lastDay(today + 1 month), yearEnd) | today |
| `generateInvoicesOfYear` (past year) | yearEnd (31 Dec) | today |

---

## Generate Month Invoice (`generateMonthInvoice`)

**Purpose:** Generate initial invoice(s) when a new agreement becomes active (onboarding).

| API | targetEnd | jobDate |
| --- | --------- | ------- |
| `generateMonthInvoice` (effectiveDate ≤ 15) | endOfMonth(effectiveDate) | today |
| `generateMonthInvoice` (effectiveDate > 15) | endOfNextMonth(effectiveDate) | today |

---

## Key Distinction

| | Monthly Billing Job | Generate All / Generate By ID |
|---|---|---|
| Purpose | Gen future invoice (next month) | Backfill missing invoices |
| Starting point | Next month (forward only) | `agreement.effectiveDate` |
| Gap detection | No | Yes (1 query per agreement) |
| Frequency | Every 15th | On demand (infrequent) |
| Run date input | 15th of month only | Any date |

---

## dueDate Rule (Dutch market)

`dueDate` is **not stored on the Invoice entity**. It is computed at PDF/UBL render time only.

```
issueDate = LocalDate.now()           ← moment the document is downloaded/rendered
dueDate   = issueDate + paymentDueDays
```

`paymentDueDays` defaults to **14**, configurable via `invoice.payment-due-days` in application config.

Compliant with Dutch *betaaltermijn* rules (ACM).

> **Note:** For backfilled invoices (past periods), `issueDate` will be the date the PDF is rendered — not the original job date. This is pre-existing behavior unrelated to the job/backfill changes.
