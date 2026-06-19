# Plan: MeterReading — TimescaleDB Hypertable

> Status: ✅ DONE — commit `1f0f7cc2` (2026-06-19)
> Branch: `feature/time-scale-db`

---

## 1. Lý do không dùng FK

`meter_reading` sẽ có lượng data rất lớn (hourly × số EAN × nhiều năm).
FK constraint trên PostgreSQL/TimescaleDB gây overhead mỗi INSERT do phải validate sang bảng `meter` — unacceptable với throughput time-series.

**Thay thế:** application-level integrity — service chỉ insert reading khi meter tồn tại, không cần DB enforce.

---

## 2. Columns đề xuất

| Column         | Type           | Nullable | Ghi chú |
|----------------|----------------|----------|---------|
| `reading_time` | TIMESTAMPTZ    | NOT NULL | Partition key cho hypertable |
| `meter_id`     | BIGINT         | NOT NULL | Loose ref tới `meter.id` — không có FK constraint |
| `ean`          | VARCHAR(18)    | NOT NULL | Denormalize EAN trực tiếp — query theo EAN không cần join |
| `value`        | DECIMAL(15,4)  | NOT NULL | Giá trị đọc tích lũy (cumulative), đơn vị xem `unit` |
| `unit`         | VARCHAR(5)     | NOT NULL | `kWh` hoặc `m3` — denormalize vì không có FK tới meter |
| `register`     | VARCHAR(5)     | NOT NULL | `T1` / `T2` / `T3` / `T4` / `TOTAL` — cần cho billing dual-tariff |
| `reading_type` | VARCHAR(20)    | NOT NULL | `ACTUAL` / `ESTIMATED` / `CORRECTED` — quan trọng cho correction flow |

### Tại sao thêm `ean`?
Vì không có FK, truy vấn theo EAN phải join `meter` → overhead trên bảng lớn.
Denormalize EAN vào đây cho phép query `WHERE ean = ? AND reading_time BETWEEN ...` trực tiếp.

### Tại sao thêm `unit`?
Không thể derive từ meter (không join, không FK). Electricity = `kWh`, gas = `m3`.
Cần khi tính billing để không hardcode logic trong service.

### Tại sao thêm `register`?
DSMR meter Hà Lan có T1 (normaal) / T2 (laag) / T3 (normaal production) / T4 (laag production).
Billing tính energiebelasting dựa trên `net_consumption = (T1+T2) - (T3+T4)` — phải có register riêng lẻ, không thể aggregate sớm.
Gas meter dùng `TOTAL`.

### Tại sao thêm `reading_type`?
Khi grid operator gửi ACTUAL reading cho period đã billing bằng ESTIMATED → cần flag để trigger correction flow (Credit/Debit Note). Không có field này thì không phân biệt được.

### Những gì KHÔNG thêm vào (scope sau):
- `source` (SMART_METER / EDSN_P4 / MANUAL) — có thể derive từ meter.is_smart_meter nếu cần
- `is_final` (final reading cho supplier switching) — add migration riêng khi cần
- `corrects_reading_at` (trỏ về reading gốc khi CORRECTED) — add sau nếu cần audit trail chi tiết

---

## 3. Hypertable setup

```sql
SELECT create_hypertable('meter_reading', 'reading_time',
    chunk_time_interval => INTERVAL '3 months',
    if_not_exists => TRUE
);
```

Chunk 3 tháng: query chính trên bảng này là eindafrekening (annual scan) — `WHERE ean = ? AND reading_time BETWEEN start_of_year AND end_of_year` chỉ cần scan 4 chunks thay vì 12 (1 month) hay 52 (1 week). Voorschot invoice không query bảng này (dùng fixed amount từ contract).

---

## 4. Index

```sql
-- Query chính: lấy readings theo meter trong period
CREATE INDEX idx_meter_reading_meter_time ON meter_reading (meter_id, reading_time DESC);

-- Query theo EAN (billing, EDSN lookup)
CREATE INDEX idx_meter_reading_ean_time ON meter_reading (ean, reading_time DESC);
```

Không index `reading_type` riêng — filter theo type thường kết hợp với meter_id/ean trong cùng query.

---

## 5. Liquibase files cần tạo

| File | Nội dung |
|------|---------|
| `20260619000001_added_entity_MeterReading.xml` | createTable + create_hypertable + indexes |

Thêm entry vào `master.xml` section incremental (cuối file).

**Không cần:**
- constraints file riêng (không có FK)
- sequence riêng (không có surrogate bigint id — primary key là `(meter_id, reading_time, register)` hoặc để TimescaleDB manage)

---

## 6. Open questions trước khi implement

- [x] Primary key: giữ surrogate `id BIGINT` — ✅ confirmed
- [x] Chunk interval: `3 months` — ✅ confirmed (eindafrekening annual scan = 4 chunks)
- [x] `ean` nullable — ✅ confirmed (JHipster generated `nullable="true"`, acceptable vì meter có thể chưa có EAN)

---

## 7. Thực tế đã làm — commit `1f0f7cc2`

**Entity & enums**
- `MeterReading.java` — đúng với columns đề xuất ở mục 2
- Enums: `MeterUnit` (KWH/M3), `MeterRegister` (T1/T2/T3/T4/TOTAL), `ReadingType` (ACTUAL/ESTIMATED/CORRECTED)
- `meterId` là loose ref, không có FK constraint — đúng quyết định mục 1

**Docker**
- `postgresql.yml` → image `timescale/timescaledb:latest-pg17`

**Liquibase migrations** (timestamps thực tế khác plan)
- `20260619035519` — createTable `meter_reading`
- `20260619035520` — enable extension, composite PK `(id, reading_time)`, hypertable 3 months, 2 indexes
- `20260619035521` — faker data 2025: EAN điện 4-register T1/T2/T3/T4 (có solar), EAN gas daily TOTAL

**Chưa làm (scope tiếp theo)**
- `MeterReadingRepositoryCustom` với queries `time_bucket` phục vụ billing engine
- Continuous aggregates
