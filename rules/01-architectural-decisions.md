# 4. Architectural Decisions — Confirmed (Option B)

## 4.1 Legal Entity Model ✅ RESOLVED

**Quyết định: Unified Legal Entity + Role**

- Không tách riêng customer_table và supplier_table theo identity cố định
- Một `LegalEntity` mang nhiều role: customer, supplier, partner, broker, reseller
- Role gán theo context của từng contract/transaction

**Implication:**

- FK trong contract/invoice trỏ vào `legal_entity_id` + `role`, không phải `customer_id` hay `supplier_id` cố định
- Tránh data duplication khi một entity vừa là supplier vừa là customer

---

## 4.2 Consumption Storage ✅ RESOLVED

**Quyết định: Time-series Database (TimescaleDB hoặc InfluxDB)**

- Raw consumption records: Time-series DB
- Metadata và summary: OLTP relational DB
- Granularity: hourly / 15-phút cho smart meter

**Implication:**

- Cần thiết kế data pipeline tách biệt cho consumption ingestion
- Query consumption cho billing phải join từ time-series DB vào OLTP DB
- Estimated vs actual phải được flag và xử lý riêng

---

## 4.3 Contract Scope ✅ RESOLVED

**Quyết định: Multi-site Contract**

- Một contract cover nhiều service location
- Một contract gồm nhiều product (electricity + gas bundle)
- Contract versioning: tạo version mới khi thay đổi, giữ nguyên bản cũ

**Implication:**

- Cần bảng linking giữa contract và service location (many-to-many)
- Pricing có thể áp dụng ở cấp contract hoặc override per-site

---

## 4.4 Pricing Model ✅ RESOLVED

**Quyết định: Versioned Tariff Engine**

- Pricing có `effective_from` / `effective_to`
- Lưu đầy đủ historical và future pricing
- B2B negotiated pricing override

**Implication:**

- Không bao giờ update pricing trực tiếp — luôn insert bản mới với effective date
- Billing engine phải lookup pricing tại đúng thời điểm consumption
- Cần index tốt trên `(tariff_id, effective_from, effective_to)`

---

## 4.5 Billing Centralization ✅ RESOLVED

**Quyết định: Consolidated Invoice — Voorschot + Eindafrekening model**

- Invoice ở cấp Account/Group (không phải per-site)
- Invoice immutable sau khi gửi
- Correction qua Credit Note / Debit Note
- **Offer** tính estimated annual consumption → chia 12 → `monthly_voorschot`
- **Tháng 1–11:** generate Voorschot Invoice với fixed amount từ offer
- **Cuối năm / cuối contract:** generate Eindafrekening = actual − total voorschot paid
  - Thừa → Credit trên final invoice
  - Thiếu → Debit trên final invoice

**Implication:**

- Offer phải có consumption estimate engine
- Voorschot amount là fixed trong contract period — không recalculate hàng tháng
- Eindafrekening reference đến toàn bộ voorschot invoices của năm
- Billing job phải aggregate consumption từ tất cả sites trong account
- Cần link giữa invoice và từng site/meter để drill-down
- Early termination → pro-rata eindafrekening

---

## 4.6 B2B Hierarchy Depth ✅ RESOLVED

**Quyết định: Tree Structure (Group → Subsidiary → Site)**

- Hỗ trợ parent-child hierarchy
- Cost center tracking ở cấp Site
- Billing consolidated ở cấp Group

**Implication:**

- Cần self-referential hoặc adjacency list/closure table cho hierarchy
- Pricing negotiation có thể ở cấp Group, apply xuống tất cả Subsidiary/Site
- Reporting cần rollup từ Site lên Group
