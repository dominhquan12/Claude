# Bounded Context: Billing

## 2.11 Invoice / Billing

Invoice thường được generate định kỳ:

- Monthly
- Quarterly

Invoice có thể gồm:

- Usage charge
- Tax
- Grid fee
- Fixed fee
- Correction
- Refund

Các vấn đề:

- Estimated invoice
- Final settlement
- Retroactive correction

**QUYẾT ĐỊNH (Option B — Consolidated Invoice):**

- Billing centralized ở cấp Account/Group (không phải per-site)
- Invoice là **immutable** — không edit sau khi gửi
- Correction thực hiện qua **Credit Note** hoặc **Debit Note** độc lập

**Billing model đã xác nhận — Voorschot + Eindafrekening:**

```
[OFFER STAGE]
    Tính estimated annual consumption
        → annual_estimate_amount = estimated_kwh × tariff + fees + tax
        → monthly_voorschot = annual_estimate_amount ÷ 12
        → Ghi vào contract

[MONTHLY — tháng 1 đến tháng 11]
    Generate Voorschot Invoice
        → Fixed amount = monthly_voorschot (từ offer)
        → Customer thanh toán mỗi tháng
        → Không phụ thuộc vào actual consumption tháng đó

[END OF YEAR hoặc END OF CONTRACT]
    Collect actual consumption (12 tháng)
        → actual_amount = actual_kwh × tariff (versioned) + fees + tax
        → total_paid = monthly_voorschot × 12
        → difference = actual_amount − total_paid

    Generate Eindafrekening (Final Settlement Invoice)
        → difference > 0: customer còn nợ thêm → Debit trên final invoice
        → difference < 0: customer trả thừa  → Credit trên final invoice
        → difference = 0: không phát sinh thêm
```

**Hai loại invoice trong hệ thống:**

| Type             | Tên              | Thời điểm                | Basis                   |
| ---------------- | ---------------- | ------------------------ | ----------------------- |
| `VOORSCHOT`      | Advance Invoice  | Hàng tháng (tháng 1–11)  | Estimated ÷ 12 từ offer |
| `EINDAFREKENING` | Final Settlement | Cuối năm / cuối contract | Actual − Total paid     |

**Implication:**

- Offer phải có consumption estimate engine (dựa trên address, historical data, customer type)
- Monthly voorschot là **fixed** trong suốt contract period — không thay đổi dù actual consumption biến động
- Eindafrekening reference đến tất cả voorschot invoices của năm
- Nếu contract kết thúc sớm (early termination): pro-rata eindafrekening cho số tháng đã dùng
- Nếu tariff thay đổi trong năm (variable contract): eindafrekening phải dùng versioned pricing tại từng thời điểm consumption

---

## 3.6 Billing Correction Flow

Ví dụ:

- Sai meter reading
- Pricing thay đổi retroactively
- Tax update

Cần:

- Credit note (hoặc debit note)
- Recalculation dựa trên versioned pricing tại thời điểm consumption
- Invoice gốc giữ nguyên (immutable)

---

## 9.6 Ubiquitous Language: Billing

### Thuật ngữ cốt lõi

| Term                        | Định nghĩa                                                                                                                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Invoice**                 | Tài liệu bất biến (immutable) ghi nhận yêu cầu thanh toán. Sau khi phát hành, không được sửa trực tiếp. Có hai loại: `VOORSCHOT` và `EINDAFREKENING`.                                            |
| **Voorschot Invoice**       | Hóa đơn tạm ứng hàng tháng. Amount = `monthly_voorschot` lấy cố định từ Offer. Không phụ thuộc vào actual consumption tháng đó. Phát sinh từ tháng 1 đến tháng N-1 của contract period.          |
| **Eindafrekening Invoice**  | Hóa đơn quyết toán cuối năm hoặc cuối contract. Amount = `actual_annual_amount − total_voorschot_paid`. Nếu dương: Debit. Nếu âm: Credit. Phải reference đến toàn bộ Voorschot Invoices của năm. |
| **Annual Actual Amount**    | Tổng chi phí thực tế của cả năm, tính từ actual consumption × versioned tariff tại đúng thời điểm tiêu thụ + fees + tax.                                                                         |
| **Total Voorschot Paid**    | Tổng tiền đã thanh toán qua các Voorschot Invoice: `monthly_voorschot × số_tháng`.                                                                                                               |
| **Settlement Difference**   | `annual_actual_amount − total_voorschot_paid`. Là basis để xác định Eindafrekening debit hoặc credit.                                                                                            |
| **Credit Note**             | Tài liệu bất biến điều chỉnh giảm một Invoice đã phát hành. Có reference đến Invoice gốc. Không sửa Invoice gốc.                                                                                 |
| **Debit Note**              | Tài liệu bất biến điều chỉnh tăng một Invoice đã phát hành. Có reference đến Invoice gốc. Không sửa Invoice gốc.                                                                                 |
| **Invoice Immutability**    | Nguyên tắc cốt lõi: một Invoice sau khi phát hành không bao giờ bị thay đổi. Mọi correction phải đi qua Credit Note hoặc Debit Note độc lập.                                                     |
| **Billing Period**          | Khoảng thời gian một Invoice bao phủ. Voorschot: 1 tháng. Eindafrekening: 12 tháng (hoặc số tháng thực tế nếu early termination).                                                                |
| **Consolidated Invoice**    | Invoice ở cấp Account/Group bao gồm consumption từ tất cả Service Locations trong billing period. Không phải per-site invoice.                                                                   |
| **Pro-rata Eindafrekening** | Eindafrekening được tính proportional khi contract kết thúc sớm (early termination) hoặc bắt đầu giữa chừng. Tính theo số ngày thực tế.                                                          |
| **Estimated Billing**       | Trường hợp actual reading chưa có khi tính Eindafrekening: dùng Consumption Estimate, flag = `ESTIMATED`. Khi actual về → generate Credit/Debit Note correction.                                 |
| **Invoice Line Item**       | Một dòng chi tiết trong Invoice tương ứng với một Tariff Line cụ thể. Cần đủ chi tiết để Customer hiểu được invoice (price transparency theo ACM).                                               |
| **Billing Job**             | Batch process chạy định kỳ để: generate Voorschot Invoices hàng tháng, trigger Eindafrekening vào cuối period, xử lý correction khi có actual readings. Phải idempotent.                         |
| **Invoice Reference**       | Eindafrekening phải link đến toàn bộ Voorschot Invoices của cùng billing year. Credit/Debit Note phải link đến Invoice gốc.                                                                      |
