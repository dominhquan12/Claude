# Bounded Context: CRM / Sales

## 2.3 Prospect / Lead

Trước khi trở thành customer:

- Có lead
- Có quotation
- Có sales flow

Ví dụ:

- User yêu cầu báo giá
- Sales contact
- So sánh supplier
- Tạo offer

**QUYẾT ĐỊNH: CRM nằm trong hệ thống**

Phạm vi trong hệ thống:

- Lead, Quotation, Offer, Contract signing, Onboarding

Ngoài hệ thống (external):

- Marketing campaigns, email automation
- Customer support ticketing
- NPS, customer feedback

---

## 7.6 CRM / Sales — Phạm vi hệ thống

**Quyết định phạm vi — ✅ CONFIRMED: CRM nằm trong hệ thống**

| Scope                                                   | Nằm trong hệ thống?  |
| ------------------------------------------------------- | -------------------- |
| Lead → Quotation → Offer → Contract signed → Onboarding | **Có** — built-in    |
| Marketing campaigns, email automation                   | **Không** — external |
| Customer support ticketing                              | **Không** — external |
| NPS, customer feedback                                  | **Không** — external |

**Ranh giới rõ ràng:** Khi Lead convert thành Customer (LegalEntity + Account) → data ownership chuyển từ Sales context sang Customer Management context.

```
[Sales Context — Internal]  ──→  [Customer Mgmt — Internal]
Lead, Quotation, Offer,          LegalEntity, Account,
Contract signing, Onboarding     Service Location
```

**Implication cho pricing:**

- Offer phải tính `annual_offer_amount` và `monthly_voorschot` tại thời điểm quotation
- Offer amount gắn với tariff version hiệu lực tại ngày offer, KHÔNG phải ngày contract start
- Consumption estimate engine cần input: address (captar_type, region), product, estimated kWh/m³

---

## 9.1 Ubiquitous Language: CRM / Sales

### Thuật ngữ cốt lõi

| Term                     | Định nghĩa                                                                                                                                                                                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Lead**                 | Một cá nhân hoặc tổ chức đã thể hiện interest với sản phẩm năng lượng nhưng chưa nhận được offer chính thức. Lead chưa có Account trong hệ thống.                                                                              |
| **Prospect**             | Lead đã được Sales qualify — đã xác định là có khả năng convert. Phân biệt với Lead raw chưa được đánh giá.                                                                                                                    |
| **Quotation Request**    | Yêu cầu từ Prospect để nhận báo giá. Kích hoạt consumption estimate engine. Cần có: địa chỉ cung cấp, loại sản phẩm, ước tính tiêu thụ, ngày cần supply.                                                                       |
| **Consumption Estimate** | Lượng điện/gas ước tính hàng năm (kWh hoặc m³) dành cho một Service Location cụ thể. Dựa trên: address region, property type, historical data (nếu có), customer segment. Dùng để tính `annual_offer_amount`.                  |
| **Offer**                | Tài liệu chính thức gửi cho Prospect, bao gồm: sản phẩm, tariff version áp dụng, `annual_offer_amount`, `monthly_voorschot`, thời hạn offer (thường 30 ngày). Trạng thái: `Draft → Sent → Accepted / Rejected / Expired`.      |
| **Offer Line**           | Một dòng đơn trong Offer tương ứng với một component giá cụ thể (ví dụ: Fixed service fee, Wholesale market consumption, Energiebelasting tier 1...). Cấu trúc offer line phải khớp hoàn toàn với pricing table đã định nghĩa. |
| **Annual Offer Amount**  | Tổng chi phí ước tính cho một năm, tính từ consumption estimate × tariff + fees + tax. Là basis để tính `monthly_voorschot`.                                                                                                   |
| **Monthly Voorschot**    | `annual_offer_amount ÷ 12`. Số tiền cố định customer trả hàng tháng trong contract period. Không thay đổi dù actual consumption biến động. Được ghi vào Contract khi Offer được Accepted.                                      |
| **Sales Conversion**     | Sự kiện khi Prospect accept một Offer và chuyển thành Customer (LegalEntity + Account). Đây là ranh giới chuyển ownership từ Sales context sang Customer Management context.                                                   |
| **Onboarding**           | Quá trình sau Sales Conversion: tạo LegalEntity, tạo Account, xác minh Service Location, xác minh EAN, thiết lập Direct Debit, submit switch request hoặc activation request tới EDSN.                                         |
| **Offer Expiry**         | Offer không được Customer respond trong thời hạn (thường 30 ngày) → trạng thái chuyển sang `Expired`. Pricing không còn valid. Cần tạo Offer mới nếu muốn tiếp tục.                                                            |

### Ranh giới quan trọng

- Offer **phải** tham chiếu đến một Tariff Version cụ thể tại ngày offer — KHÔNG phải ngày contract start.
- Sau Sales Conversion, Sales context **không** sở hữu Customer data nữa. Customer Management là context mới.
