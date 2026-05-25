# Energy Retail System (Netherlands) — Business Domain Analysis

## Goal

Phân tích nghiệp vụ cho hệ thống bán điện/gas tại Hà Lan trước khi thiết kế database.

Mục tiêu KHÔNG phải tạo schema ngay lập tức.
Hãy tập trung:

- Các actor/domain object chính
- Quan hệ giữa chúng
- Luồng nghiệp vụ
- Các trường hợp đặc thù của ngành điện/gas
- Những điểm cần lưu ý khi thiết kế hệ thống lớn
- Những ambiguity/business decision cần clarify

KHÔNG generate database schema ngay.
KHÔNG nhảy vào table/entity quá sớm.

---

# 1. Tổng quan domain

Hệ thống này là một Energy Retail Platform:

- Bán điện/gas cho customer
- Làm việc với supplier/provider
- Quản lý hợp đồng năng lượng
- Quản lý pricing/tariff
- Quản lý consumption/meter
- Billing/invoice
- B2B + B2C
- Có thể multi-supplier

Đây KHÔNG đơn giản là ecommerce.

Ngành điện/gas có nhiều domain đặc thù:

- Meter
- Consumption
- Contract period
- Dynamic pricing
- Grid operator
- Address-based supply
- Moving house
- Supplier switching
- Regulatory compliance
- Tax & tariff rules
- Forecast consumption

---

# 5. Domain complexity đặc thù

Đây là domain complexity cao.

Không nên:

- Jump ngay vào CRUD entity
- Design table quá sớm

Trước tiên cần:

- Ubiquitous language
- Bounded context
- Business flow
- Ownership
- Lifecycle

---

# 6. Bounded Context Map

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         Energy Retail Platform                                  │
│                                                                                 │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────────────┐      │
│  │   CRM/Sales  │───▶│ Customer Mgmt    │    │    Contract Mgmt         │      │
│  │ (built-in:   │    │ - LegalEntity    │───▶│  - Multi-site contract   │      │
│  │  Lead, Quote,│    │ - Role           │    │  - Lifecycle versioning  │      │
│  │  Offer, Sign,│    │ - B2B Hierarchy  │    │  - Supplier switching    │      │
│  │  Onboarding) │    │ - Account        │    └──────────┬───────────────┘      │
│  └──────────────┘    └──────────────────┘               │                      │
│                                                          ▼                      │
│  ┌──────────────────┐    ┌───────────────────┐    ┌──────────────────────┐    │
│  │  Pricing Engine  │◀───│  Billing          │◀───│   Metering           │    │
│  │ - Versioned tariff│    │ - Voorschot       │    │ - EAN/Connection pt  │    │
│  │ - EB/ODE/BTW     │    │ - Eindafrekening  │    │ - Physical meter     │    │
│  │ - B2B negotiated │    │ - Credit/Debit    │    │ - Time-series DB     │    │
│  │ - effective_from │    │   note            │    │ - Estimated/Actual   │    │
│  └──────────────────┘    │ - Consolidated    │    └──────────────────────┘    │
│                           │   invoice         │                                 │
│                           └─────────┬─────────┘                                │
│                                     │                                           │
│  ┌──────────────────┐               ▼                                           │
│  │ Supplier Mgmt    │    ┌──────────────────────┐                              │
│  │ - License track  │    │   Payment             │                              │
│  │ - EDSN integrate │    │ - Direct debit        │                              │
│  └──────────────────┘    │ - Reconciliation      │                              │
│                           └──────────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

# 8. Trạng thái phân tích

Các quyết định kiến trúc lớn: **đã confirmed** (xem `01-architectural-decisions.md`).

Deep domain analysis: **đã hoàn thành** (xem các file theo bounded context).

Ubiquitous Language: **đã hoàn thành** (xem phần UL trong từng file context).

**Bước tiếp theo hợp lý:**

- Database schema design — bắt đầu từ entity-relationship model theo thứ tự dependency:
  1. Customer Management
  2. Contract Management
  3. Metering
  4. Pricing Engine
  5. Billing
  6. Payment

KHÔNG tạo schema vội — phải theo đúng thứ tự dependency.
