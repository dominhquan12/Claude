# Timestamp vs Timestamptz — Session Findings

> Tóm tắt phiên phân tích: Hibernate timezone config, cách các external API (ENTSO-E/Yahoo/Databento/EDSN P4) trả timestamp, việc có nên đổi cột DB từ `timestamp` sang `timestamptz`, và test thực tế trên DBeaver/psql để verify hành vi.
> Liên quan: `.claude/rules/12-timezone.md`, `.claude/tasks/timezone.md`, `.claude/tasks/testdb.txt` (SQL test script dùng để verify các phát hiện dưới đây).

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

### ENTSO-E API bắt buộc request format là UTC (theo spec, không phải lựa chọn của code)

`EntsoeService.ENTSOE_FMT = DateTimeFormatter.ofPattern("yyyyMMddHHmm")` — format số thuần, **không có ký tự offset**. ENTSO-E spec định nghĩa sẵn: mọi giá trị `periodStart`/`periodEnd` gửi theo format này đều hiểu là UTC — không có cách nào khác để phân biệt vì format không mang offset. Đây là lý do code phải tự convert Amsterdam → UTC **trước khi** gửi request.

**So sánh 2 external API đã phân tích:**

| | Request format | Response format | Timezone |
|---|---|---|---|
| **ENTSO-E** | `yyyyMMddHHmm` số thuần | `"2026-06-02T22:00Z"` | **UTC cả 2 chiều**, ép cứng theo spec — API "sạch", không ambiguity |
| **EDSN P4** | (không cần khai báo ngày theo giờ) | `"2025-02-12T00:00:00.000+01:00"` | **Local Amsterdam có offset**, theo LDT convention (xem mục 3) |

---

## 3. EDSN P4 `p4Result` — LOCAL Amsterdam time, **ĐÃ FIX**

- XSD (`wsdls/P4/xsd0.xsd:5014,5120-5140`): `ReadingDateTime` type `xsd:dateTime`, comment gốc EDSN: `"Datum/tijd (dateTime) (LDT categorie-1)"` — **LDT = Lokale Datum/Tijd** (local time), khớp với golden rule `.claude/rules/12-timezone.md` #10.

### Bằng chứng thật — P4 CÓ gửi kèm offset (không phải bare local time như lo ngại ban đầu)

Mẫu response thật từ tài liệu qualification EDSN (`.claude/tasks/edsn-integration-summary.md:906-936`):
```json
{ "reading": 0.00, "readingDateTime": "2025-02-12T00:00:00.000+01:00" },
{ "reading": 0.45, "readingDateTime": "2025-02-12T07:00:00.000+01:00" }
```
`+01:00` = CET (Amsterdam mùa đông) — khớp đúng vì tháng 2 là mùa đông. EDSN luôn gắn offset Amsterdam thật (chưa từng thấy `Z`/`+00:00`), không phải bare local time thiếu offset. **Rủi ro thực tế thấp hơn** đánh giá ban đầu — nhưng code vẫn không có defensive check nếu 1 lần nào đó offset bị thiếu.

### Gap tìm thấy — ĐÃ FIX (xem `UsageService.java`)

**Code cũ (đã sửa):**
```java
Instant from = prev.getReadingDateTime().toGregorianCalendar().toInstant();
```
`XMLGregorianCalendar.toGregorianCalendar()` fallback về `TimeZone.getDefault()` (JVM server timezone, **không phải UTC**) nếu XML dateTime không có offset — vi phạm rule #4 ("never use server timezone") và #10 ("convert explicitly at integration boundary"). Nếu fallback UTC (thay vì Amsterdam) cũng SAI — vì bản chất field là local Amsterdam time (mục "LDT"), không phải UTC; coi digit là UTC sẽ lệch đúng bằng offset DST (1-2h).

Commit `ead074a4` (fix(timezone): enforce Europe/Amsterdam...) đã sửa phần group/truncate downstream trong `syncHourlyProductUsage` (`ZoneId.systemDefault()` → `BusinessConstants.MARKET_TIMEZONE`), nhưng không chạm `createUsage()` — gap đó được fix riêng trong phiên này.

**Code mới (đã áp dụng):**
```java
private Instant toInstant(XMLGregorianCalendar xml) {
    if (xml == null) return null;
    int millisecond = xml.getMillisecond();
    LocalDateTime localDateTime = LocalDateTime.of(
        xml.getYear(), xml.getMonth(), xml.getDay(),
        xml.getHour(), xml.getMinute(), xml.getSecond(),
        (millisecond == DatatypeConstants.FIELD_UNDEFINED ? 0 : millisecond) * 1_000_000
    );
    int offsetMinutes = xml.getTimezone();
    if (offsetMinutes == DatatypeConstants.FIELD_UNDEFINED) {
        return localDateTime.atZone(BusinessConstants.MARKET_TIMEZONE).toInstant();  // fallback Amsterdam, KHÔNG phải UTC hay JVM default
    }
    return localDateTime.atOffset(ZoneOffset.ofTotalSeconds(offsetMinutes * 60)).toInstant();  // dùng offset embedded nếu có
}
```
Áp dụng cho cả `createUsage()` (2 chỗ) và `processReadings()` (sort comparator — cùng lỗ hổng cũ). Compile pass (`mvn -q -o compile` exit code 0).

### Lưu ý cho tương lai — enable lại EDSN thật
Hiện tại `hourly_product_usage` KHÔNG dùng đường EDSN thật — dùng mock data (xem mục 10). Bug này không ảnh hưởng invoice hiện tại, nhưng đã fix trước để sẵn sàng khi có ai uncomment lại tích hợp EDSN (`OfferServiceImpl.java:250`: `// TODO: uncomment to call api edsn`).

---

## 4. Schema hiện tại — 100% dùng `timestamp` (no tz)

Liquibase `master.xml:11`: `datetimeType = "datetime"` (dbms=postgresql) → resolve thành `timestamp` cho **mọi** cột datetime trong hệ thống (không có cột nào dùng `timestamptz`):

`dynamic_tariff`, `hourly/daily/monthly_product_usage`, `customer`, `customer_order`, `agreement`, `service_order`, `task`, `work_order`, `invoice`, `product_process(_history)`, `mandate`, `signing_session`, `contract_signature`, `signature_audit_log`, audit columns (`created_date/last_modified_date`), envers audit tables.

Business date columns (`invoice.start_date/end_date`, `service_order`, `work_order`, `meter.start_date/end_date`) đã đúng chuẩn — dùng `date`, không phải timestamp.

**Lưu ý quan trọng:** `master.xml` chỉ định nghĩa `datetimeType` cho `dbms="postgresql"` — không có variant cho MySQL/Oracle/MSSQL. Nghĩa là project này **đã ngầm chỉ chạy được trên Postgres** dù JHipster framework hỗ trợ multi-DB — xem mục 12 (portability).

---

## 5. `timestamp` vs `timestamptz` — quy tắc chọn

| Loại dữ liệu | Kiểu Java | Kiểu cột nên dùng |
|---|---|---|
| Business date (contract, tariff effective_from/to, invoice period) | `LocalDate` | `date` |
| Timestamp nội bộ, mọi writer đi qua Hibernate/Clock UTC | `Instant` | `timestamp` (giữ convention hiện tại — vẫn ổn nếu code đúng) |
| Timestamp nhận từ external API/EDI có offset không chắc nhất quán, hoặc cần tự mô tả để audit | `OffsetDateTime` | `timestamptz` (an toàn hơn) |

### Vì sao JHipster chọn `timestamp` mặc định
JHipster generate code chạy trên nhiều DB backend (Postgres/MySQL/Oracle/MSSQL/H2) — các DB này không có type "with timezone" tương đương nhau theo cùng 1 tên/semantics (xem mục 12). Nên JHipster đẩy invariant "always UTC" lên tầng **Hibernate/JDBC** (`jdbc.time_zone=UTC`) thay vì tầng DB-native type — đảm bảo hành vi nhất quán trên mọi DB backend. Guardrail này chỉ có hiệu lực với code đi qua Hibernate — không tự động bảo vệ code hand-written bypass Hibernate, hoặc người insert tay qua tool (xem mục 10).

### Rủi ro cụ thể khi audit đa timezone (VN vs Dutch) với `timestamp`
Storage vẫn đúng nếu mọi writer đi qua Hibernate (ép UTC ở write path). Rủi ro nằm ở **đọc/hiển thị**: cột không tự mô tả là UTC → ai query raw (`psql`, BI tool, DBA) dễ hiểu lầm digit là giờ local của họ. `timestamptz` tự động convert theo `SET TIME ZONE` của session đọc — **nhưng chỉ với tool tôn trọng session GUC** (xem mục 9, DBeaver KHÔNG tôn trọng).

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

**VN chọn "ngày 19" trên chart dynamic price** → luôn là 19/06 theo lịch **Amsterdam** (business time), không phải theo giờ VN — code hiện tại đã đúng, `21giờ` UTC window (18/6 22h → 19/6 22h mùa hè) tính từ `atStartOfDay(MARKET_TIMEZONE)`. Response trả kèm offset Amsterdam (`+01:00`/`+02:00`), frontend không nên re-convert sang giờ viewer cho trục thời gian này vì sẽ làm mất đúng nghĩa slot giá.

2 loại time này **độc lập hoàn toàn với việc chọn `timestamp` hay `timestamptz`** ở DB — cả hai đều lưu absolute `Instant`/UTC, khác biệt chỉ nằm ở tầng nào (backend hay frontend) chịu trách nhiệm chọn timezone hiển thị. **DB không thể tự biết cột nào là business time, cột nào là audit time** — đây thuần túy là ý nghĩa nghiệp vụ do code quy định, không phải thuộc tính kỹ thuật của cột (đúng cho cả `timestamp` và `timestamptz`).

### Luồng FE → BE → DB → FE không bị ảnh hưởng bởi lựa chọn timestamp/timestamptz
Đã trace hop-by-hop: FE gửi business date string → BE parse qua `MARKET_TIMEZONE` → BE trả `Instant`/`OffsetDateTime` qua Jackson (`spring.jackson.time-zone: UTC`) → FE tự convert theo browser local (JS `Date`). **Toàn bộ luồng này không đổi 1 dòng** dù cột DB là `timestamp` hay `timestamptz` — vì `Instant` + Jackson UTC serialization + JS Date local-render đã cách ly hoàn toàn app khỏi kiểu cột DB. Sự khác biệt `timestamp`/`timestamptz` **chỉ lộ ra khi có người/tool đi vòng qua API, chạm thẳng vào DB** (xem mục 9, 10).

---

## 7. Nếu giữ nguyên `timestamp` — điều kiện để "vẫn ổn"

Đúng về nguyên tắc: không cần `timestamptz` nếu code giữ kỷ luật tuyệt đối — nhưng **DB không tự bắt lỗi nếu code sai** (khác với `timestamptz`, DB sẽ buộc phải có ý nghĩa offset khi insert giá trị tường minh). Điều kiện "code đúng":

- ✅ **Đã fix**: EDSN `UsageService.createUsage()` (mục 3).
- ❌ **Chưa fix**: `DynamicTariffService.syncData()` raw JDBC bind (mục 8) — hiện tại AN TOÀN với cột `timestamp` (không cần fix ngay), chỉ trở thành rủi ro NẾU đổi sang `timestamptz` trong tương lai.
- ⚠️ **Rủi ro mới phát hiện, không phải bug code**: ai đó insert tay qua DBeaver/tool với session timezone không phải UTC sẽ ghi sai data vào cột `timestamp` — không có cách nào code tự phòng vệ được, chỉ có thể phòng bằng quy trình/training (mục 10).

Gợi ý safety net khi không đổi sang `timestamptz`:
- Checkstyle/review rule cấm `ZoneId.systemDefault()`, `LocalDateTime.now()`, `new Date()`, `Calendar.getInstance()` trong `nl.crawler.custom`.
- Chạy test suite với `-Duser.timezone=America/New_York` (khác UTC và khác Amsterdam) để lộ chỗ nào đang ngầm dựa vào server timezone.
- Quy định: không insert tay qua DBeaver vào cột `timestamp` production mà không set `SET TIME ZONE 'UTC'` trước.

---

## 8. Nếu đổi sang `timestamptz` — checklist thay đổi thực tế

**Phải đổi:**
1. Liquibase changelog mới: `ALTER TABLE ... ALTER COLUMN ... TYPE timestamptz USING col AT TIME ZONE 'UTC'` cho ~35-40 cột. **Bắt buộc có `USING ... AT TIME ZONE 'UTC'`** — thiếu sẽ làm Postgres hiểu nhầm data cũ theo timezone của session chạy migration, convert sai toàn bộ data lịch sử. **Đã tự demo lỗi này thật** — xem mục 9 (Phần 2 test), lệch 7 giờ và bị DBeaver che giấu hoàn toàn.
2. Hibernate config: `preferred_instant_jdbc_type: TIMESTAMP` → `TIMESTAMP_WITH_TIMEZONE`.
3. `DynamicTariffService.syncData()` (dòng 101-107) — chỗ raw JDBC duy nhất tìm thấy bypass Hibernate, **chưa fix**:
   ```java
   // Hiện tại — an toàn với cột timestamp, nhưng SẼ SAI nếu đổi cột sang timestamptz
   ps.setObject(1, LocalDateTime.ofInstant(entity.getFrom(), ZoneOffset.UTC));
   // Cần đổi thành nếu migrate — offset tường minh, không phụ thuộc session
   ps.setObject(1, entity.getFrom().atOffset(ZoneOffset.UTC));
   ```
4. `ImportServiceImpl.importHourlyProductUsages()` — cùng pattern bind `LocalDateTime.ofInstant(...)` qua raw `JdbcTemplate`, cùng lý do cần đổi nếu migrate.
5. Nếu muốn entity **generate mới** (qua `jhipster jdl jdl.jdl`) cũng ra `timestamptz` — xem mục 13 (JHipster/JDL practical steps).

**KHÔNG cần đổi:**
- JPA entity (`nl.crawler.domain`) — field `Instant` map thẳng sang `TIMESTAMP_WITH_TIMEZONE`, không đổi type.
- Toàn bộ Service/Controller/Mapper/DTO — chỉ làm việc với `Instant`/`OffsetDateTime` trong Java, không biết cột DB là gì (xem mục 6).
- `@Query(nativeQuery = true)` qua Spring Data (`CustomerRepositoryCustom`, `RelationCustomerRepositoryCustom`, `ContactRepositoryCustom`) — vẫn bind qua Hibernate type system, không phải raw JDBC thật.
- `ProductProcessHistoryRepositoryCustom` — dùng `created_at AT TIME ZONE 'UTC'` tường minh ở cả 2 chiều so sánh → tự động tương thích dù cột là `timestamp` hay `timestamptz` (vì target zone là UTC, offset=0, digit kết quả giống nhau cả 2 trường hợp).
- JDL file (`jdl.jdl`) — field khai báo `Instant` giữ nguyên, không liên quan SQL column type.

**Không tự động fix bởi việc đổi DB type:**
- Gap ở mục 3 (`UsageService.createUsage()` / EDSN) — đã fix riêng ở tầng Java, độc lập với DB type.

**Effort thật nằm ở đâu:**
- Không phải viết SQL (rẻ) — mà ở regression test toàn bộ entity `Instant` (blast radius lớn), và lock table khi `ALTER COLUMN TYPE ... USING` rewrite toàn bảng (cần cẩn thận với bảng lớn như `hourly_product_usage`).
- Theo `CLAUDE.md`: phải qua `fix/` branch → PR vào `dev` → promote riêng từng PR `dev → tst → acc → prd`, cần reviewer vì ảnh hưởng production schema.

---

## 9. Test thực tế DBeaver vs psql — SET TIME ZONE không hoạt động giống nhau

> Script đầy đủ: `.claude/tasks/testdb.txt`. Test trên bảng tạm `tz_test`/`tz_test_wrong`, KHÔNG ảnh hưởng bảng thật.

### Phát hiện chính: psql tôn trọng `SET TIME ZONE`, DBeaver KHÔNG

Cùng 1 giá trị `timestamptz`, 2 tool cho 2 kết quả khác nhau khi đổi `SET TIME ZONE`:

| | psql (`docker exec` vào postgres container) | DBeaver |
|---|---|---|
| `SET TIME ZONE 'UTC'` rồi SELECT | Hiển thị đổi đúng theo UTC | Không đổi gì |
| `SET TIME ZONE 'Europe/Amsterdam'` rồi SELECT | Hiển thị đổi đúng theo Amsterdam | Vẫn không đổi — luôn ra cùng 1 số |

**Nguyên nhân kỹ thuật:** psql dùng **simple/text protocol** — Postgres server tự format `timestamptz` thành text theo session `TimeZone` GUC trước khi gửi, nên `SET TIME ZONE` ảnh hưởng trực tiếp. DBeaver (qua JDBC/pgJDBC) dùng **extended/binary protocol** — server gửi về raw absolute value (microsecond epoch), không format sẵn; **DBeaver tự convert ở phía client** dùng `TimeZone.getDefault()` của JVM (= timezone máy đang chạy DBeaver, ở đây là Asia/Ho_Chi_Minh +07:00) — hoàn toàn bỏ qua session GUC. Đây là hành vi phổ biến, đã được report nhiều lần trên GitHub issue của DBeaver/pgJDBC, không phải bug riêng của project.

### Hệ quả — 3 loại nhầm lẫn đã tự gặp trong buổi test

1. **Che giấu bug thật:** Ở test migration thiếu `USING` (mục 8, item 1) — data bị sai lệch 7 giờ thật, nhưng DBeaver hiển thị ra đúng số y hệt ban đầu vì offset sai (+07:00 lúc migrate) trùng đúng offset cố định DBeaver dùng để hiển thị (+07:00) — 2 lỗi tự triệt tiêu về mặt con số. Verify bằng psql: giá trị thật `2023-12-31 16:00:00+00` (sai), DBeaver hiển thị `23:00:00+0700` (giống digit gốc, gây ngộ nhận "ổn").
2. **Ngộ nhận `SET TIME ZONE` hoạt động rồi nghi data sai:** debug timezone issue trong DBeaver, chạy `SET TIME ZONE`, không thấy đổi → dễ kết luận sai "data lỗi" hoặc "code convert sai".
3. **Nhầm lẫn giữa người ở 2 nơi khác nhau:** đồng nghiệp Amsterdam và VN cùng mở DBeaver xem 1 row `timestamptz` → thấy 2 chuỗi khác nhau (`+01:00` vs `+07:00`) cho cùng 1 giá trị — dễ tưởng đang xem 2 dữ liệu khác nhau.

**Cách tránh:** luôn dùng `psql` + `SET TIME ZONE 'UTC'` làm nguồn tham chiếu khi verify migration/audit data — không tin số DBeaver hiển thị trực tiếp cho `timestamptz`.

---

## 10. Rủi ro write-side mới phát hiện — insert tay qua tool với session timezone không phải UTC

### Test: insert `now()` vào cả 2 loại cột khi DBeaver session = Asia/Ho_Chi_Minh

```sql
SET TIME ZONE 'Asia/Ho_Chi_Minh';
INSERT INTO tz_insert_test (ts_col, tstz_col) VALUES (now(), now());
-- ts_col: timestamp, tstz_col: timestamptz
```

Query lại với session UTC (giá trị THẬT):
```
ts_col                      | tstz_col
2026-07-01 16:29:04.803386  | 2026-07-01 09:29:04.803386+00
```

**`tstz_col` — ĐÚNG:** `now()` trả `timestamptz` sẵn (absolute instant), insert không cần convert gì → lưu đúng `09:29:04 UTC`.

**`ts_col` — SAI, lệch 7 giờ:** Postgres phải implicit cast `timestamptz` (từ `now()`) → `timestamp` (kiểu cột) — cast này **dùng session TimeZone hiện tại lúc insert** (+07:00) để tính wall-clock rồi bỏ offset, lưu digit `16:29:04` (giờ VN) — **không phải** `09:29:04` (giờ UTC theo convention app). Nếu app đọc lại digit này và áp convention "= UTC", sẽ hiểu nhầm thành `2026-07-01T16:29:04Z`, sai 7 giờ so với thời điểm thật.

### Test mở rộng: cùng 1 instant, insert với 3 session timezone khác nhau

```sql
-- cùng literal TIMESTAMPTZ '2026-07-01 09:29:04+00', đổi session trước mỗi insert
```
Kết quả (xem lại với session UTC):
```
session_tz | ts_col              | tstz_col
UTC        | 2026-07-01 09:29:04 | 2026-07-01 09:29:04+00
Amsterdam  | 2026-07-01 11:29:04 | 2026-07-01 09:29:04+00
VN         | 2026-07-01 16:29:04 | 2026-07-01 09:29:04+00
```

**`tstz_col`**: 3 row, **cùng 1 giá trị** — bất kể session lúc insert.
**`ts_col`**: 3 row, **3 giá trị khác nhau** (2/3 sai lệch theo đúng offset session lúc insert) — dù cùng 1 khoảnh khắc thật.

### Kết luận — rủi ro write-side độc lập với rủi ro read-side đã biết
Đây là bằng chứng cụ thể: **bất kỳ ai insert tay qua DBeaver với session timezone không phải UTC, vào cột `timestamp`, có thể vô tình ghi sai dữ liệu** — không cần cố ý, Postgres không cảnh báo gì. `timestamptz` miễn nhiễm với đúng loại lỗi này vì không có bước cast-theo-session khi insert `timestamptz` vào `timestamptz`. Rủi ro này **không áp dụng cho luồng app thật** (Hibernate luôn ép `jdbc.time_zone=UTC`) — chỉ áp dụng khi có người insert tay qua tool (dev/QA seed data thủ công).

---

## 11. Mô hình tổng quát: "1 giá trị lưu — N cách hiển thị"

```
                    1 giá trị lưu trong DB (cố định, absolute instant)
                              │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
   psql (UTC)          psql (Amsterdam)          psql (VN)
   09:29:04+00          11:29:04+01               16:29:04+07
```
`ALTER TABLE ... TYPE timestamptz` không tạo giá trị mới — chỉ gắn thêm type tag cho giá trị đã có sẵn (Postgres luôn lưu nội bộ dạng UTC absolute, bất kể `timestamp` hay `timestamptz`). **Caveat đã tự test (mục 9):** không phải tool nào cũng tôn trọng cơ chế "N cách hiển thị theo session" — DBeaver luôn chọn 1 cách hiển thị cố định, không đổi theo `SET TIME ZONE` SQL.

### Ví dụ minh họa cho người mới — phép so sánh "thư mời họp"
- **`timestamp`** = viết "họp lúc 15:00" mà không ghi rõ giờ nước nào → người Amsterdam đọc hiểu 15:00 giờ họ (đúng), người VN đọc **cùng tờ giấy** cũng hiểu 15:00 giờ họ (**sai** — vì thực ra sự kiện xảy ra lúc 20:00 giờ VN).
- **`timestamptz`** = viết "họp lúc 13:00 GMT" (mốc chung) → hệ thống tự tính: người Amsterdam thấy `15:00`, người VN thấy `20:00` — khác số nhưng **cả 2 đều đúng**, vì đều đang nói về cùng 1 khoảnh khắc.

### `timestamp` + quy ước "= UTC" KHÔNG tương đương `timestamptz`
Chỉ **giống về ý nghĩa nếu quy ước được tuân thủ hoàn hảo mãi mãi** — nhưng khác nhau về **bảo đảm**:

| | `timestamp` + quy ước UTC | `timestamptz` |
|---|---|---|
| Quy ước nằm ở đâu | Trong đầu người viết code / tài liệu — KHÔNG nằm trong schema | Nằm ngay trong type của cột |
| Ai kiểm tra vi phạm | Không ai — DB không biết | Postgres yêu cầu ý nghĩa offset rõ ràng khi ghi |
| Đã tự chứng minh lỗi | **CÓ** — test `now()` mục 10 | Không xảy ra trong cùng test |

---

## 12. Portability sang DBMS khác (nếu tương lai đổi khỏi Postgres)

| DB | Type tương đương absolute instant | Type tương đương naive |
|---|---|---|
| MySQL/MariaDB | `TIMESTAMP` (tự convert theo session `time_zone` — **giống `timestamptz`**, dù tên gây nhầm) | `DATETIME` (naive, giống Postgres `timestamp`) |
| Oracle | `TIMESTAMP WITH TIME ZONE` | `TIMESTAMP` |
| SQL Server | `datetimeoffset` (lưu offset gốc, không normalize UTC — semantics khác Postgres) | `datetime2` |
| H2 (dev/test) | `TIMESTAMP WITH TIME ZONE` | `TIMESTAMP` |

**Điểm mấu chốt:** dù chọn `timestamp` hay `timestamptz` hôm nay, migrate DB khác **luôn cần remap lại** (timestamp→DATETIME hoặc timestamptz→TIMESTAMP MySQL) — không bên nào "miễn phí". Chọn `timestamptz` không tạo thêm lock-in mới.

**Với project này cụ thể:** đã lock-in Postgres từ quyết định khác, lớn hơn nhiều — **TimescaleDB** (`.claude/rules/01-architectural-decisions.md` §4.2) cho consumption time-series, extension chỉ tồn tại trên Postgres. Nếu thật sự migrate khỏi Postgres tương lai, việc đầu tiên phải giải quyết là toàn bộ kiến trúc TimescaleDB — remap vài chục cột timestamp chỉ là phần nhỏ trong 1 cuộc migrate quy mô lớn hơn nhiều, không phải rủi ro riêng do chọn `timestamptz`.

---

## 13. JHipster/JDL — cần làm gì để entity generate SAU NÀY ra `timestamptz`

`jdl.jdl` hiện có **26 field `Instant`** across nhiều entity — mọi entity generate từ JDL đều ra `timestamp` vì **1 điểm duy nhất**: `master.xml:11`.

**Chưa thực hiện — cần làm nếu muốn áp dụng:**

1. **`master.xml`** — đổi property (1 lần, có hiệu lực vĩnh viễn cho mọi entity generate sau):
   ```xml
   <property name="datetimeType" value="timestamptz" dbms="postgresql"/>
   ```
   An toàn khi chạy lại `jhipster jdl jdl.jdl` — đã verify: JHipster generator chỉ append `<include>` mới tại marker `<!-- jhipster-needle-liquibase-add-... -->` (dòng 65, 101, 133), không đụng lại block `<property>` (dòng 6-12) trên các lần chạy sau.

2. **`application.yml`** — không do JDL sinh ra, sửa tay:
   ```yaml
   hibernate.type.preferred_instant_jdbc_type: TIMESTAMP_WITH_TIMEZONE
   ```

3. **Migration riêng cho bảng ĐÃ TỒN TẠI** — đổi property chỉ ảnh hưởng entity generate SAU, không tự fix bảng cũ. Vẫn cần changelog `ALTER ... USING ... AT TIME ZONE 'UTC'` (mục 8, item 1).

**KHÔNG cần đổi:** `jdl.jdl` (field `Instant` giữ nguyên), entity Java (`nl.crawler.domain.*`, field vẫn `Instant`), fake-data CSV loader (`type="date"` chỉ là hint parse CSV, không phải SQL type thật).

**Nên test trước:** generate 1 entity mới nhỏ sau khi đổi property, confirm changelog sinh ra đúng `timestamptz`, trước khi áp dụng migration cho bảng cũ.

---

## 14. Quyết định — nên đổi hay giữ?

**Khuyến nghị:** Không cấp bách, nhưng đáng làm về lâu dài — không phải vì lo DB portability (đã giải ở mục 12 — project lock-in Postgres qua TimescaleDB), mà vì `timestamptz` cho 2 lớp safety net mà `timestamp` không có:
1. **Write-side**: chống lỗi insert tay qua tool với session timezone sai (mục 10) — `timestamp` hoàn toàn không có bảo vệ này.
2. **Self-documentation**: schema tự mô tả ý nghĩa, không cần ai "nhớ hộ" quy ước UTC.

**Trạng thái hiện tại (đã làm trong phiên này):**
- ✅ Fix `UsageService.createUsage()` / `processReadings()` — EDSN boundary, không phụ thuộc JVM default timezone nữa (mục 3).
- ❌ Chưa fix `DynamicTariffService.syncData()` / `ImportServiceImpl.importHourlyProductUsages()` raw JDBC bind — an toàn với `timestamp` hiện tại, chỉ cần fix NẾU migrate `timestamptz` (mục 8).
- ❌ Chưa đổi `master.xml`/`application.yml` cho `timestamptz` (mục 13) — chỉ mới lên kế hoạch, chưa thực thi.
- ❌ Chưa có migration changelog cho ~35-40 cột hiện tại (mục 8, item 1).

**Ưu tiên nếu tiếp tục:**
1. Quyết định có migrate `timestamptz` hay không (dựa trên mục 10, 12, 14 — lợi ích write-side safety vs effort regression test).
2. Nếu có: đổi `master.xml` + `application.yml` trước (mục 13), test với entity mới, rồi mới viết migration changelog cho bảng cũ.
3. Fix raw JDBC bind ở `DynamicTariffService`/`ImportServiceImpl` trước khi chạy migration (mục 8, item 3-4).
4. Theo `CLAUDE.md`: mọi thay đổi trên qua `fix/` branch riêng → PR vào `dev` → promote từng PR `dev → tst → acc → prd`.
