# Bounded Context: Contract Management

## 2.7 Contract

Contract là core domain.

Customer mua điện/gas thông qua contract.

Contract có:

- Start date
- End date
- Supplier
- Product
- Pricing model
- Terms
- Renewal policy

Các loại:

- Fixed contract
- Variable contract
- Dynamic pricing
- Spot market pricing

**QUYẾT ĐỊNH (Option B — Multi-site Contract):**

- Một contract có thể cover nhiều service location (multi-site)
- Một contract có thể gồm nhiều product (electricity + gas bundle)
- Một site có thể có contract chồng nhau trong thời gian supplier switching
- Contract có lifecycle versioning — không edit trực tiếp, tạo version mới
- Có early termination fee và auto-renew policy
- Contract lifecycle: `Draft → Offered → Accepted → Active → Suspended → Terminated/Expired`

---

## 2.8 Product

Product không chỉ là "electricity".

Ví dụ:

- Electricity
- Gas
- Green energy
- Solar package
- Dynamic tariff package

Một contract có thể:

- Chứa nhiều product

Ví dụ:

- Electricity + gas bundle

---

## 3.1 Customer Onboarding Flow

Flow:

- Lead
- Quotation
- Offer
- Contract signed
- Activate supply
- Start billing

---

## 3.3 Moving House

Customer chuyển nhà:

- End supply tại address cũ
- Start supply tại address mới

Không đơn giản chỉ update address — đây là hai contract transaction độc lập.

---

## 3.5 Contract Renewal

Contract:

- Sắp hết hạn
- Renew tự động
- Offer mới
- Pricing mới

Renewal tạo contract version mới — không edit contract cũ.

---

## 7.1 Contract Lifecycle — States & Valid Transitions

```
                    ┌──────────────────────────────────────────────┐
                    │                                              │

[Draft] ──→ [Offered] ──→ [Accepted] ──→ [Active] ──→ [Terminated]
               │               │              │               ↑
               │               │              ↓               │
               ↓               ↓         [Suspended]  [Early Termination]
           [Expired]       [Rejected]        │
           (offer timeout)                   ↓
                                        [Active]
                                             │
                                             ↓
                                        [Expired] (end date reached)
                                             │
                                             ↓
                                   [Renewed] → tạo contract version mới
```

**Valid transitions và business rules:**

| Từ        | Đến        | Điều kiện                                |
| --------- | ---------- | ---------------------------------------- |
| Draft     | Offered    | Sales gửi offer cho customer             |
| Offered   | Accepted   | Customer ký                              |
| Offered   | Rejected   | Customer từ chối                         |
| Offered   | Expired    | Quá thời hạn offer (thường 30 ngày)      |
| Accepted  | Active     | Effective start date đến                 |
| Active    | Suspended  | Non-payment / Dispute                    |
| Active    | Terminated | Early termination request                |
| Active    | Expired    | End date tự nhiên                        |
| Suspended | Active     | Issue resolved                           |
| Suspended | Terminated | Không giải quyết được                    |
| Expired   | Renewed    | Auto-renew hoặc customer ký contract mới |

**Điểm quan trọng:**

- **Versioning:** Mỗi lần thay đổi terms/pricing → tạo `ContractVersion` mới, không mutate contract gốc.
- **Overlapping:** Khi supplier switching, contract `Active` cũ và contract `Accepted` mới tồn tại cùng lúc tại cùng supply point — phân biệt bằng `effective_from` tại supply point level.
- **Termination date:** Ngày request termination ≠ ngày effective termination (cần notice period, thường 30 ngày).

---

## 9.3 Ubiquitous Language: Contract Management

### Thuật ngữ cốt lõi

| Term                        | Định nghĩa                                                                                                                                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Contract**                | Thỏa thuận cung cấp năng lượng giữa một Customer (Account) và một Supplier, cho một hoặc nhiều Service Location, với một hoặc nhiều Product. Không bao giờ bị edit trực tiếp — mọi thay đổi tạo Contract Version mới.          |
| **Contract Version**        | Snapshot bất biến của Contract tại một thời điểm. Mỗi lần terms/pricing thay đổi → insert version mới, giữ nguyên version cũ. Contract luôn có ít nhất 1 version.                                                              |
| **Contract Lifecycle**      | Chuỗi trạng thái hợp lệ: `Draft → Offered → Accepted → Active → Suspended → Terminated / Expired`.                                                                                                                             |
| **Contract Product Line**   | Một dòng trong Contract tương ứng với một Product (electricity hoặc gas) tại một Service Location cụ thể. Một Contract multi-site multi-product có nhiều Contract Product Lines.                                               |
| **Effective Start Date**    | Ngày Contract chính thức có hiệu lực — ngày bắt đầu billing và supply. Khác với ngày ký Contract.                                                                                                                              |
| **Contract Period**         | Khoảng thời gian từ Effective Start Date đến End Date. Toàn bộ pricing, voorschot, và metering phải nằm trong period này.                                                                                                      |
| **Auto-renew Policy**       | Quy tắc tự động gia hạn khi Contract sắp hết hạn. Các giá trị: `NONE`, `SAME_TERMS`, `NEW_OFFER`. Nếu `NEW_OFFER` → trigger Sales flow tạo Offer mới trước ngày expiry.                                                        |
| **Early Termination**       | Kết thúc Contract trước End Date theo yêu cầu của Customer. Khác với `notice date` (ngày request) và `termination date` (ngày effective, thường cộng thêm notice period 30 ngày). Phát sinh Early Termination Fee nếu áp dụng. |
| **Early Termination Fee**   | Phí phạt khi Customer terminate contract trước hạn. Được định nghĩa tại Contract Version và tính theo công thức (ví dụ: số tháng còn lại × fixed amount, hoặc % consumption estimate).                                         |
| **Notice Period**           | Khoảng thời gian từ khi Customer yêu cầu terminate/switch đến ngày effective. Thường 30 ngày theo quy định ACM Hà Lan.                                                                                                         |
| **Supply Point Assignment** | Liên kết giữa một Contract Product Line và một Connection Point (EAN) cụ thể. Một contract có thể cover nhiều Supply Point Assignments.                                                                                        |
| **Overlapping Supply**      | Trạng thái tạm thời khi switching supplier: Contract cũ còn `Active` và Contract mới đã `Accepted` tại cùng một Supply Point. Phân biệt bằng `effective_from` tại Supply Point level.                                          |
| **Suspension**              | Trạng thái Contract tạm dừng do: non-payment, dispute, hoặc yêu cầu từ grid operator. Supply có thể bị ngắt. Cần giải quyết trong thời hạn để tránh Termination.                                                               |
