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
