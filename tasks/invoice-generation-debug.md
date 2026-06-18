# Invoice Generation — Debug & Implementation Notes

> Branch: `fix/invoice-generation-agreement-date-bounds`
> Commit: `d93cfbfd` — #1388: generate month invoice, year invoice, end contract

---

## 1. end-products / end-contracts có cần gọi lại generateAnnualInvoicesOnAnniversary không?

**Kết luận: KHÔNG cần.**
- `end-products` và `end-contracts` đã dùng `createInvoiceForProducts(activeDate, inactiveDate)` — đủ rồi.
- `generateAnnualInvoicesOnAnniversary` dành cho agreement đang chạy hit anniversary, không phải contract đã terminate.
- Call trong `acceptOffer` là side-effect sai chỗ — nên chuyển ra `@Scheduled` job riêng.

---

## 2. Bug: end product 1,2 → end contract → invoice của product 3 không được lưu

**Root cause:**
- Tất cả products có `activeDate = "2024-02-22"` (hardcoded trong `CustomerPersistenceServiceImpl.java:338,374,448`).
- `createInvoiceForProducts` check duplicate bằng `existsByAgreement_IdAndStartDateAndInvoiceTypeIn(agreementId, startDate, [YEAR,END])`.
- `end-products(1,2)` tạo END invoice với `startDate=2024-02-22` → khi `end-contracts(3)` chạy, check trả `true` → invoice p3 bị skip.

**Fix (InvoiceRepositoryCustom.java + InvoiceService.java):**
- Thêm method: `findByAgreement_IdAndStartDateAndEndDateAndInvoiceTypeIn(...)` vào repo.
- Split `alreadyExists` check theo invoice type:
  - **YEAR**: dùng check gốc `existsByAgreement_IdAndStartDate...` (any invoice at same startDate blocks).
  - **END**: dùng product ID comparison — deserialize `invoice.relation` (JSON), so sánh sorted productIds. Khác product group → không coi là duplicate → tạo invoice riêng.

---

## 3. Bug: end-contracts gen ra YEAR invoice cho product 3 (sai)

**Root cause:**
- Fix trước (product ID check cho cả YEAR) vô tình phá logic cũ: END invoice của [p1,p2] vốn block YEAR [2024-02-22, 2025-02-22], nhưng sau khi thêm product ID check thì [p1,p2] ≠ [p3] → không block → YEAR invoice được tạo.

**Fix (InvoiceService.java:501-524):**
- YEAR invoice: giữ check gốc — bất kỳ YEAR hoặc END invoice nào tại cùng `startDate` đều block.
- END invoice: dùng product ID exact match.
- Kết quả: END invoice của [p1,p2] tại `startDate=2024-02-22` block YEAR của [p3] cho cùng period ✓.

---

## 4. Bug: NullPointerException "augend is null" tại InvoiceCalculationService.java:456

**Root cause:** `TotalCalcItem` có field null, `BigDecimal::add` trong `reduce` không chấp nhận null operand.
**Fix:** Wrap bằng `zeroIfNull()` (đã có sẵn trong class) trong method `aggregate()` — áp dụng cho cả 3 fields: `totalAmountExcludeVat`, `totalVat`, `totalAmountIncludeVat`.

---

## 5. Bug: end product 1,2 → sinh cả YEAR invoice cho [p1,p2] (sai)

**Root cause:**
- `calculateInvoice` truyền `activeDate = product.activeDate` (= `agreement.effectiveDate`) vào `createInvoiceForProducts`.
- `createInvoiceForProducts` loop từ `activeDate` → `inactiveDate`, sinh YEAR invoice cho mỗi 12-tháng đầy đủ + END invoice cho phần lẻ.
- YEAR invoice nên do job `generateAnnualInvoicesOnAnniversary` xử lý cho toàn bộ products, không phải end flow.

**Fix:**

*`CustomerServiceImpl.calculateInvoice`:*
- Tính `lastAnniversary` = anniversary gần nhất của `agreement.effectiveDate` ≤ `inactiveDate`.
- Truyền `lastAnniversary` làm `activeDate` → period < 12 tháng → `createInvoiceForProducts` chỉ sinh 1 END invoice.

*`InvoiceService.generateAnnualInvoicesOnAnniversary`:*
- Bỏ filter `productStatus == ACTIVE/NEW` ngoài loop (sai khi job chạy sau khi products đã INACTIVE).
- Move filter vào trong loop mỗi period, dùng **time-overlap**: `activeDate <= periodEnd && (inactiveDate == null || inactiveDate > periodStart)`.
- Kết quả: job luôn đưa đúng products vào đúng YEAR invoice, bất kể thứ tự chạy với end flow.

**Tại sao không cần gap-fill / ordering guarantee:**
- YEAR invoice check by `startDate` (= `periodStart`) — độc lập với END invoice (khác `startDate`).
- Job crash rồi retry → idempotent, tự fill đúng products theo time-overlap.

---

## 6. Feature: generateAnnualInvoicesOnAnniversary — API endpoint mới

**Endpoint:** `POST /invoice/generate/annual`
**Input:** `AnnualInvoiceGenerateRequest { invoiceDate: LocalDate }`
**Guard:** `invoiceDate > today` → `400 INVOICE_DATE_IN_FUTURE__BILLING`

**Luồng:**
1. `agreementRepository.findAllByDate(date)` — lấy agreements có `effectiveDate <= date AND (expirationDate IS NULL OR expirationDate >= date)`.
2. Filter `isOlderThanOneYear`: `date >= effectiveDate + 1 year`.
3. Loop qua từng full 12-month period từ `effectiveDate`:
   - Filter products theo **time-overlap**: `activeDate <= periodEnd && (inactiveDate == null || inactiveDate > periodStart)`.
   - Check `existsByAgreement_IdAndStartDateAndInvoiceTypeIn([YEAR, END])` → idempotent.
   - Tạo YEAR invoice với `relation = JSON { productIds (sorted), endDate, invoiceScope: "YEAR" }`.

**Tại sao time-overlap thay vì filter theo status hiện tại:**
Job có thể chạy sau khi products đã INACTIVE (do end-products flow chạy trước). Filter theo status tại thời điểm chạy sẽ bỏ sót products đã kết thúc nhưng thuộc về period đó.

---

## 7. Refactor: bỏ supplierId khỏi một số API

- `generateInvoicesOfYear(customerId, supplierId, year)` → `generateInvoicesOfYear(customerId, year)`
- `generateInvoicesWithCustomDate(supplierId, invoiceDate)` → `generateInvoicesWithCustomDate(invoiceDate)`

Cả hai giờ dùng `customerOrderRepository.findAllByCustomer(customer, ACCEPTED)` / `findByOrderStatus(ACCEPTED)` thay vì lọc theo supplier.

**Lý do:** Customer có thể có orders từ nhiều supplier — tất cả đều cần xử lý, không nên lọc theo 1 supplier cụ thể.

---

## 8. Fix: AgreementRepositoryCustom — query hỗ trợ null expirationDate

**Trước:** `WHERE :givenDate BETWEEN a.effectiveDate AND a.expirationDate`
→ Fail khi `expirationDate IS NULL` (open-ended agreement).

**Sau:**
```sql
WHERE a.effectiveDate <= :givenDate
AND (a.expirationDate IS NULL OR a.expirationDate >= :givenDate)
```

**Lý do:** `OfferServiceImpl` đã comment out `agreement.setExpirationDate(...)` → agreements mới có `expirationDate = null`.

---

## 9. Fix: OfferServiceImpl — comment out setExpirationDate

```java
// agreement.setExpirationDate(customerOrder.getDesiredDate().plusMonths(12));
```

Agreements giờ là open-ended (expirationDate = null) — expirationDate chỉ set khi contract thực sự kết thúc qua end-contracts flow.

---

## Files changed (commit d93cfbfd)

| File | Thay đổi |
|------|---------|
| `InvoiceController.java` | Thêm `generateAnnualInvoices` endpoint; bỏ supplierId khỏi 2 methods |
| `InvoiceService.java` | Thêm `generateAnnualInvoicesOnAnniversary`, `createYearInvoice`; refactor `createInvoiceForProducts` (split YEAR/END duplicate check); refactor `generateInvoicesOfYear`, `generateInvoicesWithCustomDate` |
| `InvoiceRepositoryCustom.java` | Thêm `existsByAgreement_IdAndStartDateAndInvoiceTypeIn`, `findByAgreement_IdAndStartDateAndEndDateAndInvoiceTypeIn` |
| `CustomerServiceImpl.java` | `calculateInvoice`: tính `lastAnniversary` trước khi gọi `createInvoiceForProducts` |
| `AgreementRepositoryCustom.java` | Fix query hỗ trợ null expirationDate |
| `InvoiceCalculationService.java` | `aggregate()`: zeroIfNull cho 3 fields |
| `OfferServiceImpl.java` | Comment out `setExpirationDate` |
| `api.yml` | Thêm `AnnualInvoiceGenerateRequest` schema + `/invoice/generate/annual` endpoint; bỏ supplierId khỏi `InvoiceOfYearRequest`, `InvoiceRequest` |
| `ErrorName.java` | Thêm `INVOICE_DATE_IN_FUTURE__BILLING` |
| `messages.properties`, `messages_nl.properties` | Message cho error mới |
