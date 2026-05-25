# Bounded Context: Metering

## 2.5 Meter

Meter là domain object cực kỳ quan trọng.

Ví dụ:

- Electricity meter
- Gas meter
- Smart meter

Meter:

- Có serial number
- Có reading
- Có consumption history
- Có activation/deactivation
- Có owner/operator

Các vấn đề nghiệp vụ:

- Meter replacement
- Meter transfer
- Smart meter polling
- Missing readings
- Estimated readings

---

## 2.6 Connection / Utility Point

Ở châu Âu thường có:

- EAN
- Connection point
- Delivery point

Đây là định danh điểm cấp điện/gas.

Không phải meter.

Một location:

- Có thể đổi meter
- Nhưng connection point vẫn giữ nguyên

=> Cần phân biệt:

- Physical meter
- Logical supply point

---

## 2.10 Consumption

Consumption là dữ liệu sử dụng điện/gas.

Ví dụ:

- kWh
- m3 gas

Nguồn dữ liệu:

- Smart meter
- Manual reading
- Estimated reading

Consumption:

- Theo giờ
- Theo ngày
- Theo tháng

Khối lượng data có thể rất lớn.

**QUYẾT ĐỊNH (Option B — Time-series Database):**

- Consumption data lưu trong **Time-series DB** (TimescaleDB hoặc InfluxDB)
- KHÔNG dùng OLTP relational DB cho raw consumption records
- Granularity: hourly (smart meter có thể 15-phút)
- OLTP DB chỉ lưu metadata (meter info, account, period summary)
- Data ingestion từ grid operator qua batch EDI hoặc API (không self-collect)
- Estimated reading được flag riêng; khi có actual reading → retroactive correction

---

## 2.13 Grid Operator / Network Operator

Ở Hà Lan có:

- Grid operator riêng
- Supplier riêng

Supplier bán điện.
Grid operator quản lý hạ tầng.

Ví dụ:

- Stedin
- Liander
- Enexis

Cần hiểu:

- Hệ thống có integrate với grid operator không?
- Có import meter reading không?
- Có supplier switching flow không?

---

## 3.4 Meter Replacement

Meter có thể:

- Hỏng
- Được thay mới

Consumption history cần continuity:

- Ghi lại final reading của meter cũ
- Ghi lại initial reading của meter mới
- Không được gián đoạn dữ liệu tại EAN/connection point

---

## 7.5 Consumption Correction Flow

**Kịch bản:** Invoice tháng 1 đã gửi dựa trên estimated reading. Tháng 3, grid operator gửi actual reading cho tháng 1.

```
[Actual reading received for past period]
        │
        ▼
[System phát hiện: period này đã có invoice, flag = ESTIMATED]
        │
        ▼
[Recalculate: actual_amount vs billed_amount]
        │
        ├── actual < billed ──▶ Generate Credit Note
        │                        - Reference: original invoice ID
        │                        - Amount: difference
        │                        - Period: original billing period
        │
        └── actual > billed ──▶ Generate Debit Note
                                 - Reference: original invoice ID
                                 - Amount: difference
                                 - Period: original billing period
        │
        ▼
[Update consumption record: ESTIMATED → CORRECTED, link actual_reading_id]
        │
        ▼
[Payment adjustment: credit/debit applied to next invoice hoặc separate payment]
```

**Immutability rule:**

- Invoice gốc **không bao giờ bị sửa**.
- Mọi correction đi qua document mới (Credit Note / Debit Note).
- Audit trail phải trace được: `Invoice → CreditNote → ActualReading`.

**Retroactive pricing change (hiếm nhưng có):**

- Pricing thay đổi retroactively (ví dụ grid fee điều chỉnh bởi regulator) → toàn bộ affected invoices phải recalculate.
- Đây là batch process cần queue và idempotency.

---

## 9.4 Ubiquitous Language: Metering

### Thuật ngữ cốt lõi

| Term                                 | Định nghĩa                                                                                                                                                                                                     |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Connection Point**                 | Điểm kết nối logic với lưới điện/gas của grid operator. Định danh bằng **EAN** (Energy Identification Code). Không thay đổi khi meter vật lý được thay.                                                        |
| **EAN (Energy Identification Code)** | Mã định danh duy nhất 18 chữ số của Connection Point. Ví dụ: `871687600001234567`. Đây là key dùng trong tất cả EDI/EDSN communication.                                                                        |
| **Meter**                            | Thiết bị vật lý đo lường consumption tại một Connection Point. Một Connection Point có thể có nhiều Meter trong lịch sử (do replacement). Có serial number riêng.                                              |
| **Smart Meter**                      | Meter có khả năng truyền dữ liệu tự động (P1 protocol hoặc AMR). Cung cấp hourly granularity. Đủ điều kiện cho dynamic pricing.                                                                                |
| **Conventional Meter**               | Meter đọc thủ công. Granularity: monthly hoặc theo schedule grid operator.                                                                                                                                     |
| **Meter Reading**                    | Giá trị số thực tế ghi lại tại một thời điểm cụ thể — đơn vị kWh hoặc m³. Có hai loại: `ACTUAL` (đọc thực) và `ESTIMATED` (ước tính).                                                                          |
| **Meter Reading Type**               | `ACTUAL`: từ grid operator hoặc smart meter. `ESTIMATED`: được hệ thống hoặc grid operator tính toán khi không có actual. `CORRECTED`: actual reading thay thế cho estimated reading cũ.                       |
| **Consumption Record**               | Dữ liệu consumption được tính từ hai Meter Reading liên tiếp: `consumption = reading_end − reading_start`. Lưu trong Time-series DB. Có flag `is_estimated`.                                                   |
| **Consumption Granularity**          | Độ chi tiết của data: `HOURLY` (smart meter), `DAILY`, `MONTHLY`. Billing engine cần aggregate đến `ANNUAL` để tính tiered energiebelasting.                                                                   |
| **Net Consumption**                  | Tổng consumption sau khi trừ net production (áp dụng khi Customer có solar panel và được Saldering). `net_consumption = gross_consumption − net_production`. Dùng làm basis cho energiebelasting.              |
| **Net Production**                   | Lượng điện tái tạo được tạo ra vượt quá consumption, trả lại lưới. Áp dụng Saldering với KVB customers có solar.                                                                                               |
| **Captar Type**                      | Loại kết nối xác định grid fee (Capaciteitstarief). Điện: theo công suất kết nối (3×25A, 3×35A...). Gas: theo band tiêu thụ hàng năm (0–500 m³, 501–4.000 m³, 4.001–40.000 m³). Phải lưu tại Connection Point. |
| **Meter Replacement**                | Sự kiện thay thế Meter vật lý tại một Connection Point. Yêu cầu: ghi Final Reading của meter cũ, ghi Initial Reading của meter mới, đảm bảo continuity của Consumption Record tại EAN.                         |
| **Final Reading**                    | Meter Reading được ghi tại thời điểm kết thúc supply — dùng cho supplier switching hoặc contract termination.                                                                                                  |
| **Initial Reading**                  | Meter Reading đầu tiên khi bắt đầu supply hoặc sau khi meter replacement.                                                                                                                                      |
| **Missing Reading**                  | Trường hợp không có Meter Reading cho một period nhất định. Hệ thống phải: flag kỳ đó là `ESTIMATED`, sử dụng interpolation hoặc average, update khi actual reading đến.                                       |
| **EDSN**                             | Energy Data Services Netherlands — tổ chức trung gian quản lý trao đổi metering data giữa các supplier và grid operator tại Hà Lan. Supplier nhận meter data qua EDSN — không tự collect.                      |
| **P4 Protocol**                      | Giao thức EDI dùng giữa grid operator và EDSN để trao đổi metering data. Hệ thống cần integration layer để parse và import.                                                                                    |
| **Retroactive Correction**           | Khi actual reading đến sau khi đã billing với estimated → hệ thống recalculate difference và generate Credit Note hoặc Debit Note. Invoice gốc giữ nguyên.                                                     |
