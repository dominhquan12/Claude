# Timestamp vs Timestamptz — Session Findings

> Tóm tắt phiên phân tích: Hibernate timezone config, cách các external API (ENTSO-E/Yahoo/Databento/EDSN P4) trả timestamp, và việc có nên đổi cột DB từ `timestamp` sang `timestamptz`.
> Liên quan: `.claude/rules/12-timezone.md`, `.claude/tasks/timezone.md`.

---

## 1. Hibernate config hiện tại (application.yml)

```yaml
hibernate.jdbc.time_zone: UTC
hibernate.timezone.default_storage: NORMALIZE
hibernate.type.preferred_instant_jdbc_type: TIMESTAMP
hibernate.id.new_generator_mappings: true
```

- `jdbc.time_zone: UTC` — ép JDBC session timezone = UTC cho mọi connection Hibernate quản lý, bất kể server/OS đang chạy ở timezone nào.
- `default_storage: NORMALIZE` — `OffsetDateTime`/`ZonedDateTime` được normalize về UTC trước khi lưu.
- `preferred_instant_jdbc_type: TIMESTAMP` — field `Instant` map sang SQL `TIMESTAMP` (không tz), không phải `TIMESTAMPTZ`.
- `id.new_generator_mappings: true` — không liên quan timezone, chỉ điều khiển JPA 2.0+ sequence generator.

Pipeline kết quả: `Instant (Java) → JDBC session UTC → SQL TIMESTAMP thuần → DB luôn chứa UTC digit`.

---

## 2. `fetchDynamicTariffPrices` — timezone theo từng provider

`DynamicTariffService.fetchDynamicTariffPrices()` chọn 1 trong 3 provider (`dynamic-price.active-provider`):

| Provider | File | Response timezone | Xử lý |
|---|---|---|---|
| ENTSO-E (điện) | `EntsoeService.java` | UTC thật (`"2026-06-02T22:00Z"`) | Parse `OffsetDateTime.parse(...).toInstant()` — đúng |
| Yahoo Finance (gas, default) | `YahooFinancePriceService.java` | Unix epoch (UTC tuyệt đối) | `Instant.ofEpochSecond(...).atZone(AMSTERDAM)` chỉ để bucket theo trading day — đúng |
| Databento (gas, alt) | `DatabentoPriceService.java` | Epoch nanosecond | Tương tự Yahoo — đúng |
| Nieuwe Stroom (**inactive**) | `NieuwStroomService.java` | Không rõ — không có convert tường minh | Rủi ro nếu re-enable, cần verify lại format thật |

Request luôn convert Amsterdam local date → UTC window tường minh trước khi gọi API (`ZonedDateTime...withZoneSameInstant(UTC)`), không hardcode offset — tự động handle DST.

**Ví dụ cụ thể (đã verify với code):** chọn ngày `19/06` (mùa hè, CEST=UTC+2) → request window UTC = `18/6 22:00 → 19/6 22:00`. Mùa đông (CET=UTC+1) sẽ là `23:00 → 23:00` — do dùng `ZoneId.of("Europe/Amsterdam")` với `withZoneSameInstant`, tự đúng qua DST.

---

## 3. EDSN P4 `p4Result` — LOCAL Amsterdam time, không phải UTC

- XSD (`wsdls/P4/xsd0.xsd:5014`): `ReadingDateTime` type `xsd:dateTime`, comment gốc EDSN: `"Datum/tijd stand (LDT1)"` — **LDT = Lokale Datum/Tijd** (local time), khớp với golden rule `.claude/rules/12-timezone.md` #10.

### Gap tìm thấy — chưa fix
`UsageService.createUsage()` (~dòng 205-206):
```java
Instant from = prev.getReadingDateTime().toGregorianCalendar().toInstant();
```
`XMLGregorianCalendar.toGregorianCalendar()` fallback về `TimeZone.getDefault()` (JVM server timezone) nếu XML dateTime không có offset — vi phạm rule #4 ("never use server timezone") và #10 ("convert explicitly at integration boundary").

Commit `ead074a4` (fix(timezone): enforce Europe/Amsterdam...) đã sửa phần group/truncate downstream trong `syncHourlyProductUsage` (`ZoneId.systemDefault()` → `BusinessConstants.MARKET_TIMEZONE`), **nhưng không chạm `createUsage()`** — gap này vẫn tồn tại.

**Đề xuất fix (chưa làm):**
```java
Instant from = LocalDateTime.parse(rawReadingDateTime, DSMR_FORMATTER)
    .atZone(BusinessConstants.MARKET_TIMEZONE)
    .toInstant();
```

---

## 4. Schema hiện tại — 100% dùng `timestamp` (no tz)

Liquibase `master.xml:11`: `datetimeType = "datetime"` (dbms=postgresql) → resolve thành `timestamp` cho **mọi** cột datetime trong hệ thống (không có cột nào dùng `timestamptz`):

`dynamic_tariff`, `hourly/daily/monthly_product_usage`, `customer`, `customer_order`, `agreement`, `service_order`, `task`, `work_order`, `invoice`, `product_process(_history)`, `mandate`, `signing_session`, `contract_signature`, `signature_audit_log`, audit columns (`created_date/last_modified_date`), envers audit tables.

Business date columns (`invoice.start_date/end_date`, `service_order`, `work_order`, `meter.start_date/end_date`) đã đúng chuẩn — dùng `date`, không phải timestamp.

---

## 5. `timestamp` vs `timestamptz` — quy tắc chọn

| Loại dữ liệu | Kiểu Java | Kiểu cột nên dùng |
|---|---|---|
| Business date (contract, tariff effective_from/to, invoice period) | `LocalDate` | `date` |
| Timestamp nội bộ, mọi writer đi qua Hibernate/Clock UTC | `Instant` | `timestamp` (giữ convention hiện tại — vẫn ổn) |
| Timestamp nhận từ external API/EDI có offset không chắc nhất quán, hoặc cần tự mô tả để audit | `OffsetDateTime` | `timestamptz` (an toàn hơn) |

### Vì sao JHipster chọn `timestamp` mặc định
JHipster generate code chạy trên nhiều DB backend (Postgres/MySQL/Oracle/MSSQL/H2) — các DB này không có type "with timezone" tương đương nhau (MySQL không có `TIMESTAMPTZ`; SQL Server `datetimeoffset` lưu offset gốc, semantics khác Postgres). Nên JHipster đẩy invariant "always UTC" lên tầng **Hibernate/JDBC** (`jdbc.time_zone=UTC`) thay vì tầng DB-native type — đảm bảo hành vi nhất quán trên mọi DB backend. Guardrail này chỉ có hiệu lực với code đi qua Hibernate — không tự động bảo vệ code hand-written bypass Hibernate (chính là 2 gap ở mục 3 và 6).

### Rủi ro cụ thể khi audit đa timezone (VN vs US) với `timestamp`
Storage vẫn đúng (Hibernate ép UTC ở write path — VN 10:00 ICT và US 06:00 EDT cùng ghi ra UTC digit nhất quán, sort/so sánh đúng). Rủi ro nằm ở **đọc/hiển thị**: cột không tự mô tả là UTC → ai query raw (`psql`, BI tool, DBA) dễ hiểu lầm digit là giờ local của họ. `timestamptz` tự động convert theo `SET TIME ZONE` của session đọc — `timestamp` thì không, phải tự convert ở tầng consumer.

---

## 6. Business time vs Audit time — 2 loại temporal semantics riêng biệt

Xác nhận qua `DynamicTariffsController.getAllDynamicTariffsByTime()`:
```java
Instant start = LocalDate.parse(startDate).atStartOfDay(BusinessConstants.MARKET_TIMEZONE).toInstant();
...
.from(OffsetDateTime.ofInstant(hourStart, BusinessConstants.MARKET_TIMEZONE))
```

| | Business time | Audit time |
|---|---|---|
| Ví dụ | dynamic tariff day, EB tier theo năm, contract effective_from/to, billing period | created_date, last_modified_date, signed_at, event_timestamp |
| Neo theo | **Europe/Amsterdam cố định** — không đổi theo viewer | **Viewer đang xem** — đổi theo từng người |
| Ai xử lý | Backend (`BusinessConstants.MARKET_TIMEZONE`), bất kể request từ đâu | Frontend — convert theo local browser của viewer |
| Sai thì | Sai boundary ngày, sai EB tier, sai billing → sai tiền | Chỉ gây hiểu lầm hiển thị, data không sai |

**VN chọn "ngày 19" trên chart dynamic price** → luôn là 19/06 theo lịch **Amsterdam** (business time), không phải theo giờ VN — code hiện tại đã đúng. Response trả kèm offset Amsterdam (`+01:00`/`+02:00`), frontend không nên re-convert sang giờ viewer cho trục thời gian này vì sẽ làm mất đúng nghĩa slot giá.

2 loại time này **độc lập với việc chọn `timestamp` hay `timestamptz`** ở DB — cả hai đều lưu absolute `Instant`/UTC, khác biệt chỉ nằm ở tầng nào (backend hay frontend) chịu trách nhiệm chọn timezone hiển thị.

---

## 7. Nếu giữ nguyên `timestamp` — điều kiện để "vẫn ổn"

Đúng về nguyên tắc: không cần `timestamptz` nếu code giữ kỷ luật tuyệt đối — nhưng **DB không tự bắt lỗi nếu code sai** (khác với `timestamptz`, DB sẽ buộc phải có offset khi insert). Điều kiện "code đúng" hiện **chưa được đảm bảo 100%** — còn 2 gap chưa fix (mục 3, và mục 8 dưới).

Gợi ý safety net khi không đổi sang `timestamptz`:
- Checkstyle/review rule cấm `ZoneId.systemDefault()`, `LocalDateTime.now()`, `new Date()`, `Calendar.getInstance()` trong `nl.crawler.custom`.
- Chạy test suite với `-Duser.timezone=America/New_York` (khác UTC và khác Amsterdam) để lộ chỗ nào đang ngầm dựa vào server timezone.

---

## 8. Nếu đổi sang `timestamptz` — checklist thay đổi thực tế

**Phải đổi:**
1. Liquibase changelog mới: `ALTER TABLE ... ALTER COLUMN ... TYPE timestamptz USING col AT TIME ZONE 'UTC'` cho ~35-40 cột. **Bắt buộc có `USING ... AT TIME ZONE 'UTC'`** — thiếu sẽ làm Postgres hiểu nhầm data cũ theo timezone của session chạy migration, convert sai toàn bộ data lịch sử.
2. Hibernate config: `preferred_instant_jdbc_type: TIMESTAMP` → `TIMESTAMP_WITH_TIMEZONE`.
3. `DynamicTariffService.syncData()` (dòng 101-107) — chỗ raw JDBC duy nhất tìm thấy bypass Hibernate:
   ```java
   // Hiện tại — naive LocalDateTime, phụ thuộc session TimeZone của raw connection
   ps.setObject(1, LocalDateTime.ofInstant(entity.getFrom(), ZoneOffset.UTC));
   // Cần đổi thành — offset tường minh, không phụ thuộc session
   ps.setObject(1, entity.getFrom().atOffset(ZoneOffset.UTC));
   ```

**KHÔNG cần đổi:**
- JPA entity (`nl.crawler.domain`) — field `Instant` map thẳng sang `TIMESTAMP_WITH_TIMEZONE`, không đổi type.
- Toàn bộ Service/Controller/Mapper/DTO — chỉ làm việc với `Instant`/`OffsetDateTime` trong Java, không biết cột DB là gì.
- `@Query(nativeQuery = true)` qua Spring Data (`CustomerRepositoryCustom`, `RelationCustomerRepositoryCustom`, `ContactRepositoryCustom`) — vẫn bind qua Hibernate type system, không phải raw JDBC thật.
- `ProductProcessHistoryRepositoryCustom` — dùng `created_at AT TIME ZONE 'UTC'` tường minh ở cả 2 chiều so sánh → tự động tương thích dù cột là `timestamp` hay `timestamptz` (vì target zone là UTC, offset=0, digit kết quả giống nhau cả 2 trường hợp).

**Không tự động fix bởi việc đổi DB type:**
- Gap ở mục 3 (`UsageService.createUsage()` / EDSN) — bug nằm ở tầng parse Java, xảy ra *trước khi* JDBC nhận giá trị. Đổi cột DB không sửa được, phải fix riêng.

**Effort thật nằm ở đâu:**
- Không phải viết SQL (rẻ) — mà ở regression test toàn bộ entity `Instant` (blast radius lớn vì field này có ở gần hết mọi bounded context), và lock table khi `ALTER COLUMN TYPE ... USING` rewrite toàn bảng (cần cẩn thận với bảng lớn như `hourly_product_usage`).
- Theo `CLAUDE.md`: phải qua `fix/` branch → PR vào `dev` → promote riêng từng PR `dev → tst → acc → prd`, cần reviewer vì ảnh hưởng production schema.

---

## 9. Quyết định — nên đổi hay giữ?

**Khuyến nghị:** Không cấp bách, nhưng đáng làm về lâu dài — không phải vì lo DB portability (project đã lock-in Postgres qua quyết định dùng **TimescaleDB**, xem `.claude/rules/01-architectural-decisions.md` §4.2 — TimescaleDB là extension chỉ có trên Postgres), mà vì `timestamptz` cho safety net ở tầng DB mà `timestamp` không có.

**Ưu tiên trước khi đổi schema:**
1. Fix gap EDSN (`UsageService.createUsage()`) — mục 3.
2. Fix raw JDBC bind (`DynamicTariffService.syncData()`) — mục 8.
3. Sau đó mới cân nhắc migration `timestamp → timestamptz` như một sáng kiến hardening riêng, có kế hoạch test/rollout rõ ràng — không gộp vào 1 PR nhỏ.
