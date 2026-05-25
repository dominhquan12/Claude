# Bounded Context: Pricing Engine

## 2.9 Tariff / Pricing

Pricing trong ngành năng lượng rất phức tạp.

Có thể gồm:

- Fixed monthly fee
- Usage-based fee
- Peak/off-peak
- Dynamic hourly pricing
- Tax
- Grid fee
- Environmental fee

Ví dụ:

- Giá khác nhau theo giờ
- Giá khác nhau theo consumption tier
- Giá khác nhau theo region

**QUYẾT ĐỊNH (Option B — Versioned Tariff Engine):**

- Pricing có `effective_from` / `effective_to` — không update trực tiếp
- Lưu đầy đủ historical pricing (phục vụ audit và billing correction)
- Có future pricing (schedule giá trước khi có hiệu lực)
- Có customer-specific pricing (B2B negotiated tariff override)
- Pricing gắn với supplier, có thể override theo customer segment hoặc per-deal

**Cấu trúc giá chi tiết — Electricity (per offer line):**

| Offer line (EN)                           | Offer line (NL)                            | Volume unit | Tariff basis                 | VAT |
| ----------------------------------------- | ------------------------------------------ | ----------- | ---------------------------- | --- |
| Fixed service fee                         | Vaste leveringskosten                      | per year    | fixed (EUR/year)             | 21% |
| Wholesale market consumption              | Groothandelsmarkt inkoop                   | kWh/year    | EUR/kWh                      | 21% |
| Top-up fee consumption                    | Inkoopvergoeding inkoop                    | kWh/year    | EUR/kWh                      | 21% |
| Wholesale market net production           | Groothandelsmarkt teruglevering            | kWh/year    | EUR/kWh (negative)           | 21% |
| Top-up fee net production                 | Verkoopvergoeding teruglevering            | kWh/year    | EUR/kWh                      | 21% |
| Energy tax tier 1 (0–2.900 kWh)           | Energiebelasting 0 t/m 2.900 kWh           | kWh/year    | EUR/kWh (tiered)             | 21% |
| Energy tax tier 2 (2.901–10.000 kWh)      | Energiebelasting 2.901 t/m 10.000 kWh      | kWh/year    | EUR/kWh (tiered)             | 21% |
| Energy tax tier 3 (10.001–50.000 kWh)     | Energiebelasting 10.001 t/m 50.000 kWh     | kWh/year    | EUR/kWh (tiered)             | 21% |
| Energy tax tier 4 (50.001–10.000.000 kWh) | Energiebelasting 50.001 t/m 10.000.000 kWh | kWh/year    | EUR/kWh (tiered)             | 21% |
| Tax discount residential                  | Vermindering energiebelasting              | per year    | fixed (EUR/year, negative)   | 21% |
| Grid operator costs                       | Netbeheerkosten (Captar-based)             | per day     | EUR/day (by connection type) | 21% |

**Cấu trúc giá chi tiết — Gas (per offer line):**

| Offer line (EN)                          | Offer line (NL)                                             | Volume unit | Tariff basis            | VAT |
| ---------------------------------------- | ----------------------------------------------------------- | ----------- | ----------------------- | --- |
| Fixed service fee                        | Vaste leveringskosten                                       | per year    | fixed (EUR/year)        | 21% |
| Wholesale market consumption             | Groothandelsmarkt inkoop                                    | m³/year     | EUR/m³                  | 21% |
| Top-up fee consumption                   | Inkoopvergoeding inkoop                                     | m³/year     | EUR/m³                  | 21% |
| Energy tax tier 1 (0–1.000 m³)           | Energiebelasting 0 t/m 1.000 m³                             | m³/year     | EUR/m³ (tiered)         | 21% |
| Energy tax tier 2 (1.001–170.000 m³)     | Energiebelasting 1.001 t/m 170.000 m³                       | m³/year     | EUR/m³ (tiered)         | 21% |
| Energy tax tier 3 (170.001–1.000.000 m³) | Energiebelasting 170.001 t/m 1.000.000 m³                   | m³/year     | EUR/m³ (tiered)         | 21% |
| Grid operator costs                      | Netbeheerkosten (Captar-based, tiered by annual usage band) | per day     | EUR/day (by usage band) | 21% |

**Các khái niệm pricing đặc thù:**

- **Captar (Capaciteitstarief):** Grid fee cho điện tính theo công suất kết nối (ví dụ: 3×25A). Cho gas tính theo band tiêu thụ hàng năm (0–500 m³ = \*, 501–4.000 m³ = **, 4.001–40.000 m³ = \***). Phải lưu `captar_type` tại connection point.
- **Energiebelasting (EB):** Thuế năng lượng tiered — rate giảm dần khi consumption tăng. Rate thay đổi hàng năm theo quyết định chính phủ → bắt buộc versioned.
- **ODE (Opslag Duurzame Energie):** Đã được gộp vào Energiebelasting từ 2023 — KHÔNG còn là dòng riêng trên invoice.
- **BTW (VAT):** 21% áp dụng trên tất cả các dòng.
- **Vermindering energiebelasting:** Khoản giảm trừ cố định hàng năm cho hộ gia đình/residential — chỉ áp dụng cho KVB (Kleinverbruik) + Verblijfsfunctie = true.
- **Saldering (Net-metering):** Áp dụng cho KVB customer có solar panel. Sản lượng điện tái tạo được trừ vào consumption trước khi tính giá. Chỉ applicable với KVB segment.
- **KVB (Kleinverbruik):** Phân khúc tiêu thụ nhỏ (thường B2C và SME nhỏ). Xác định eligibility cho Vermindering và Saldering.

---

## 7.3 Pricing Engine — Billing Flow & Eindafrekening Calculation

**Nguyên tắc cốt lõi:** Billing hàng tháng **không phụ thuộc** vào actual meter reading. Monthly invoice chỉ là khoản thanh toán tạm ứng cố định được tính từ offer.

**Luồng đầy đủ:**

```
[OFFER STAGE — tính estimated annual amount]
        │
        ▼
[Estimate annual consumption dựa trên:]
    - Address / region
    - Historical data (nếu có)
    - Customer type (B2B vs B2C)
    - Product (electricity / gas / bundle)
        │
        ▼
[Tính annual_offer_amount theo pricing formula:]

  Electricity:
    = fixed_service_fee
    + (net_consumption_kwh × wholesale_rate)
    + (net_consumption_kwh × topup_fee_consumption)
    - (net_production_kwh × wholesale_return_rate)      ← nếu có solar/Saldering
    + (net_production_kwh × topup_fee_production)       ← nếu có solar/Saldering
    + energiebelasting(net_consumption_kwh, tiered)
    - vermindering_eb                                   ← nếu KVB + residential
    + grid_fee_captar(captar_type, days_in_year)
    + btw(21% over all above)

  Gas:
    = fixed_service_fee
    + (consumption_m3 × wholesale_rate)
    + (consumption_m3 × topup_fee)
    + energiebelasting(consumption_m3, tiered)
    + grid_fee_captar(captar_type, days_in_year)
    + btw(21% over all above)

        │
        ▼
[monthly_voorschot = annual_offer_amount ÷ 12]
[Ghi vào contract — cố định trong suốt contract period]

─────────────────────────────────────────────────────

[MONTHLY JOB — tháng 1 đến tháng N-1]
        │
        ▼
[Generate Voorschot Invoice]
    → Amount = monthly_voorschot (lấy từ offer — KHÔNG tính lại)
    → Không cần actual reading
    → Customer thanh toán fixed amount

─────────────────────────────────────────────────────

[END OF YEAR hoặc END OF CONTRACT]
        │
        ▼
[Collect actual consumption từ grid operator / time-series DB]
        │
        ▼
[Tính actual_annual_amount theo cùng pricing formula]
    - Dùng versioned tariff tại ĐÚNG THỜI ĐIỂM consumption (không phải thời điểm billing)
    - Tính tiered energiebelasting dựa trên actual total consumption
    - Tính grid_fee_captar dựa trên actual captar_type và actual days

        │
        ▼
[total_voorschot_paid = monthly_voorschot × số_tháng_đã_thanh_toán]
[difference = actual_annual_amount − total_voorschot_paid]

        │
        ├── difference > 0 ──▶ Customer nợ thêm → Debit trên Eindafrekening
        │
        ├── difference < 0 ──▶ Customer trả thừa → Credit trên Eindafrekening
        │
        └── difference = 0 ──▶ Không phát sinh thêm
        │
        ▼
[Generate Eindafrekening Invoice]
    → Type = EINDAFREKENING
    → Kèm breakdown: actual consumption per line item
    → Reference đến tất cả Voorschot invoices của năm
```

**Versioned pricing lookup — bắt buộc:**

Mỗi consumption record phải được tính với tariff **effective tại thời điểm tiêu thụ**:

```
actual_line_amount(offer_line, period) =
    SUM(
        consumption_unit[timestamp]
        × tariff_rate[offer_line][effective_at = timestamp]   ← versioned lookup
    )
```

Energiebelasting tiered được tính trên **total annual consumption**, không phải từng tháng riêng lẻ — vì tier phụ thuộc vào tổng kWh / m³ trong năm.

**Trường hợp đặc biệt:**

| Case                                           | Xử lý                                                                              |
| ---------------------------------------------- | ---------------------------------------------------------------------------------- |
| Contract kết thúc sớm (early termination)      | Pro-rata eindafrekening cho số ngày/tháng thực tế                                  |
| Tariff thay đổi giữa năm (variable contract)   | Eindafrekening dùng versioned pricing tại từng thời điểm consumption               |
| Actual reading chưa có khi tính eindafrekening | Dùng estimated reading, flag = ESTIMATED; generate Credit/Debit Note khi actual về |
| Saldering (net-metering)                       | Net production được trừ khỏi consumption trước khi áp energiebelasting             |
| KVB customer                                   | Được áp Vermindering energiebelasting (khoản giảm trừ cố định hàng năm)            |

---

## 9.5 Ubiquitous Language: Pricing Engine

### Thuật ngữ cốt lõi

| Term                              | Định nghĩa                                                                                                                                                                                                                                                       |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Tariff**                        | Tập hợp tất cả Tariff Lines áp dụng cho một Product (electricity hoặc gas) trong một period. Tariff gắn với Supplier và có thể override theo Customer Segment hoặc per-deal.                                                                                     |
| **Tariff Version**                | Snapshot bất biến của Tariff tại một `effective_from` date. Không bao giờ update trực tiếp — luôn insert Tariff Version mới. Phải lưu historical và future versions.                                                                                             |
| **Tariff Line**                   | Một component đơn trong Tariff tương ứng với một Offer Line cụ thể. Ví dụ: `FIXED_SERVICE_FEE`, `WHOLESALE_CONSUMPTION`, `ENERGIEBELASTING_TIER_1`...                                                                                                            |
| **Tariff Line Type**              | Phân loại Tariff Line: `FIXED` (EUR/năm), `VARIABLE_PER_UNIT` (EUR/kWh hoặc EUR/m³), `TIERED` (rate thay đổi theo consumption band), `CAPTAR_DAILY` (EUR/ngày theo captar_type).                                                                                 |
| **Effective From / Effective To** | Khoảng thời gian một Tariff Version có hiệu lực. Không được có gap hoặc overlap trong cùng một Tariff. Future pricing được phép schedule trước.                                                                                                                  |
| **Versioned Pricing Lookup**      | Nguyên tắc bắt buộc: mọi billing calculation phải lookup tariff rate tại đúng thời điểm consumption — KHÔNG phải thời điểm billing.                                                                                                                              |
| **Energiebelasting (EB)**         | Thuế năng lượng của chính phủ Hà Lan. Tiered: rate giảm dần khi consumption tăng. Rate thay đổi hàng năm → bắt buộc versioned. Áp dụng cả electricity và gas với tiers khác nhau.                                                                                |
| **EB Tier**                       | Một dải consumption trong thang thuế Energiebelasting. Điện: Tier 1 (0–2.900 kWh), Tier 2 (2.901–10.000 kWh), Tier 3 (10.001–50.000 kWh), Tier 4 (50.001–10.000.000 kWh). Gas: 3 tiers. Rate áp dụng theo tổng annual consumption — KHÔNG tính từng tháng riêng. |
| **ODE (Opslag Duurzame Energie)** | Đã được gộp vào Energiebelasting từ 2023. **Không còn là Tariff Line riêng** trên invoice.                                                                                                                                                                       |
| **BTW (VAT)**                     | Thuế giá trị gia tăng Hà Lan: 21%. Áp dụng trên tất cả Tariff Lines bao gồm cả Energiebelasting và grid fee.                                                                                                                                                     |
| **Vermindering Energiebelasting** | Khoản giảm trừ cố định hàng năm cho residential customers. Điều kiện: KVB segment + Verblijfsfunctie = true. Là Tariff Line âm trên invoice. Thay đổi hàng năm → bắt buộc versioned.                                                                             |
| **Captar (Capaciteitstarief)**    | Grid fee tính theo công suất kết nối (electricity) hoặc tiêu thụ hàng năm (gas). Rate = EUR/ngày theo Captar Type. Là Tariff Line `CAPTAR_DAILY`.                                                                                                                |
| **Wholesale Rate**                | Giá thị trường bán buôn. Có thể là fixed trong contract period (fixed contract) hoặc thả nổi theo spot market (dynamic/variable contract).                                                                                                                       |
| **Top-up Fee**                    | Khoản phụ phí supplier thêm vào trên Wholesale Rate. Bao gồm: `topup_fee_consumption` (cho điện mua vào) và `topup_fee_production` (cho điện trả lại lưới).                                                                                                      |
| **Negotiated Tariff**             | Tariff riêng được thỏa thuận cho một B2B Customer cụ thể, override Standard Tariff của Supplier. Gắn với LegalEntity ID + Contract.                                                                                                                              |
| **Customer Segment Override**     | Tariff adjustment áp dụng theo phân khúc khách hàng (ví dụ: KVB discount, enterprise rate). Ưu tiên thấp hơn Negotiated Tariff.                                                                                                                                  |
| **Saldering (Net-metering)**      | Cơ chế cho phép KVB customers có solar panel: Net Production được khấu trừ khỏi Gross Consumption trước khi tính Energiebelasting. Tính trên annual net consumption.                                                                                             |
| **Annual Settlement Basis**       | Energiebelasting tiered tính trên tổng tiêu thụ cả năm — không tính theo từng tháng. Điều này ảnh hưởng đến cách aggregate consumption trong Eindafrekening.                                                                                                     |
