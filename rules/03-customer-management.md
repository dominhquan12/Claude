# Bounded Context: Customer Management

## 2.1 Customer

Customer là bên mua điện/gas.

Có thể gồm:

- B2C customer
- B2B customer

### B2C

Ví dụ:

- Cá nhân
- Hộ gia đình
- Người thuê nhà

Đặc điểm:

- Thường 1 hoặc vài địa chỉ sử dụng
- Billing đơn giản hơn
- Contract ít phức tạp hơn

### B2B

Ví dụ:

- Công ty
- Nhà máy
- Chuỗi cửa hàng
- Văn phòng

Đặc điểm:

- Multi-location
- Nhiều meter
- Có hierarchy
- Có negotiated pricing
- Contract phức tạp
- Consumption lớn
- Có SLA riêng

**QUYẾT ĐỊNH (Option B — B2B Tree Hierarchy):**

- Có hierarchy tree: `Enterprise Group → Subsidiary → Site`
- Billing: Consolidated (centralized) — invoice ở cấp Group/Account
- Có parent-child hierarchy (tree structure, không phải flat)
- Có cost center tracking ở cấp Site

---

## 2.2 Supplier / Legal Entity

Supplier là bên cung cấp điện/gas.

Ví dụ:

- Energy company
- Energy wholesaler

Supplier:

- Có pricing riêng
- Có tariff riêng
- Có contract riêng
- Có branding riêng

Quan trọng:
Một supplier CÓ THỂ đồng thời là customer.

Ví dụ:

- Một công ty vừa mua điện cho văn phòng
- Đồng thời bán điện lại cho customer khác

**QUYẾT ĐỊNH (Option B — Unified Legal Entity + Role):**

- Một `LegalEntity` tồn tại độc lập, mang nhiều role đồng thời:
  - customer
  - supplier
  - partner
  - broker
  - reseller
- KHÔNG tách riêng `customer_table` và `supplier_table` theo identity cố định
- Role được gán theo context của từng contract/transaction
- Identity của entity không thay đổi — chỉ role thay đổi

---

## 2.4 Address / Service Location

Điện/gas gắn chặt với địa điểm sử dụng.

Rất quan trọng:
Customer != location

Phân tầng:

```
LegalEntity (Customer/Supplier/...)
    └── Account
          └── Service Location (địa chỉ thực tế dùng điện/gas)
                └── Connection Point / EAN (logical supply point)
                      └── Meter (physical device)
                            └── Meter Reading
                                  └── Consumption Record
```

Một customer:

- Có nhiều service location

Một location:

- Có nhiều meter

Ví dụ:

- Công ty có 30 văn phòng
- Mỗi văn phòng có điện + gas meter riêng

Cần phân biệt:

- Billing address
- Legal address
- Service address

---

## 7.4 B2B Hierarchy — Edge Cases & Depth

**Cấu trúc tree đã confirm:** `Enterprise Group → Subsidiary → Site`

**Giới hạn độ sâu:** Tối đa **4 cấp** để tránh phức tạp hóa query.

**Edge cases:**

| Case                             | Mô tả                                                   | Giải pháp                                                                                                |
| -------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **EC1 — Site thuộc nhiều Group** | Một site thuộc hai business unit?                       | KHÔNG. Site chỉ thuộc 1 parent. Nếu cần chia cost → dùng cost center allocation                          |
| **EC2 — Restructuring**          | Công ty mua lại/sáp nhập, site chuyển Group             | Track lịch sử ownership với `effective_from/to`. Billing history giữ nguyên — không re-assign invoice cũ |
| **EC3 — Partial billing**        | Tập đoàn muốn billing theo Subsidiary, không theo Group | Billing level phải configurable per-account. Mỗi node có `billing_entity = true/false`                   |
| **EC4 — B2C trong B2B group**    | Chủ DN nhỏ dùng chung account cho VP và nhà riêng       | Phân biệt `account_type = B2B / B2C` tại cấp Account, không phải LegalEntity                             |

---

## 7.9 Identity Resolution, Contacts & Representatives

### Vấn đề cốt lõi

Khi một người (nhân viên, chủ doanh nghiệp, ZZP'er) submit offer request, hệ thống cần phân biệt:

- **Ai là người liên lạc** (contact person — người điền form, nhận email)
- **Ai là contract holder** (legal entity — bên ký hợp đồng, chịu nghĩa vụ pháp lý)

Contract Holder luôn là **Legal Entity (công ty hoặc cá nhân)**, không bao giờ là nhân viên đại diện.

---

### Persons — anchor giữa Keycloak và hệ thống

Cần bảng `persons` để tách **người thật** (authentication identity) khỏi **contact role** (authorization per legal entity):

```
persons
  id              uuid [pk]
  keycloak_sub    varchar [unique, immutable]   // Keycloak UUID — anchor bất biến
  email           varchar [unique]              // mutable — notification target, sync từ JWT
  first_name      varchar
  last_name       varchar
  phone           varchar
```

**Nguyên tắc:**

- `keycloak_sub` = immutable UUID từ JWT `sub` claim — không bao giờ thay đổi dù email đổi
- `email` = mutable — chỉ dùng để gửi notification, auto-sync từ JWT mỗi khi login
- Lookup sau login: `persons WHERE keycloak_sub = JWT.sub` — **KHÔNG** lookup bằng email

---

### Identity theo loại customer

**B2B — identity = KVK number**

```
Công ty A → kvk_number: 12345678  ← định danh duy nhất, bất biến
Email nhân viên               ← chỉ là communication channel, có thể thay đổi
```

- Deduplication check khi tạo offer mới: `legal_entities.kvk_number` (KHÔNG phải email)
- Email cá nhân của nhân viên hoặc chủ doanh nghiệp được phép dùng — không bắt buộc company email
- ZZP'er và SME nhỏ thường chỉ có một email dùng cho mọi việc

**B2C — identity = persons.keycloak_sub**

```
Ông A → persons.keycloak_sub: "kc-uuid-99"  ← anchor bất biến
         persons.email: "a@gmail.com"         ← notification, có thể đổi
Địa chỉ nhà                                  ← service_location, KHÔNG phải identity
```

- Deduplication check: `persons.email` tại thời điểm tạo account (unique constraint)
- Address là `service_location` — nơi deliver điện/gas, thay đổi khi chuyển nhà
- Khi chuyển nhà: cùng một LegalEntity, hai Service Location khác nhau

---

### Contacts — role của một người trong một tổ chức

Bảng `contacts` tách **người liên lạc** khỏi **legal entity**, liên kết qua `person_id`:

```
contacts
  person_id         → persons.id              // người thật — KHÔNG lưu email trực tiếp
  legal_entity_id   → legal_entities.id       // null trước khi Sales Conversion
  lead_id           → leads.id
  role: SUBMITTER | AUTHORIZED_SIGNATORY | BILLING_CONTACT | INVOICE_RECIPIENT
  has_signing_authority: boolean              // tekenbevoegdheid (NL)
  is_primary: boolean
```

Một người (`person`) có thể có nhiều contact records tại nhiều legal entity:

```
persons: { id: 99, email: "jan@gmail.com", keycloak_sub: "kc-uuid-99" }

contacts:
  { person_id: 99, legal_entity_id: [Jan's home B2C], role: PRIMARY }
  { person_id: 99, legal_entity_id: [Bedrijf A], role: SUBMITTER }
  { person_id: 99, legal_entity_id: [Bedrijf B], role: BILLING_CONTACT }
```

Một LegalEntity có thể có nhiều contacts với các role khác nhau:

```
LegalEntity (Công ty A)
  ├── Contact (role=SUBMITTER): Procurement manager — người điền form
  └── Contact (role=AUTHORIZED_SIGNATORY): CEO — người có tekenbevoegdheid, nhận link ký
```

**Signing link** gửi đến `AUTHORIZED_SIGNATORY`, không phải `SUBMITTER`.

---

### Login flow — context switching

```
[1] Login Keycloak (email/password)
      → JWT: { sub: "kc-uuid-99", email: "jan@gmail.com" }

[2] Backend: persons WHERE keycloak_sub = JWT.sub → person_id = 99
    Nếu JWT.email ≠ persons.email → auto-update persons.email (email đã đổi)

[3] Frontend load context picker:
      SELECT legal_entity_id, legal_entity.name, contacts.role
      FROM contacts WHERE person_id = 99

[4] User chọn context (ví dụ: Bedrijf A, legal_entity_id = 7)

[5] Mọi API request kèm header: X-Legal-Entity-Id: 7

[6] Backend middleware mỗi request:
      contact = contacts WHERE person_id = 99 AND legal_entity_id = 7
      → role = BILLING_CONTACT → áp permission tương ứng
```

**Guard bắt buộc tại backend:** Validate `person → legal_entity` membership trên mọi request — không tin header mù. Nếu person không có contact record tại legal_entity đó → 403.

**Behavior khi chưa chọn context:**

| Trường hợp              | Behavior                     |
| ----------------------- | ---------------------------- |
| Đúng 1 context          | Auto-select, skip picker     |
| Nhiều context           | Bắt buộc chọn trước khi dùng |
| B2C thuần, không có B2B | Vào thẳng home account       |

---

### Keycloak account — tạo khi nào

**QUYẾT ĐỊNH: Tạo Keycloak account ngay khi contact được thêm vào hệ thống** — dùng Keycloak "invited user" flow (required action: `UPDATE_PASSWORD`).

| Role                   | Tạo Keycloak account?         | Lý do                                                                           |
| ---------------------- | ----------------------------- | ------------------------------------------------------------------------------- |
| `SUBMITTER`            | **Có**                        | Cần portal để track offer status                                                |
| `BILLING_CONTACT`      | **Có**                        | Cần portal để xem invoice, payment                                              |
| `AUTHORIZED_SIGNATORY` | **Có** (nếu cần portal) / tùy | Signing link hoạt động không cần login, nhưng tạo sẵn để tránh merge complexity |
| `INVOICE_RECIPIENT`    | **Không**                     | Chỉ nhận PDF qua email, không cần login                                         |

Flow khi tạo contact:

```
Contact được thêm vào hệ thống
  → Tạo Keycloak user (email, required_action: UPDATE_PASSWORD)
  → persons.keycloak_sub = Keycloak UUID ngay lập tức
  → Keycloak gửi invite email tự động
  → Không có "pending person without keycloak_sub" — merge flow không cần thiết
```

---

### Email change — rules và ảnh hưởng

**Validation trước khi cho phép đổi email:**

1. Email mới chưa tồn tại trong Keycloak realm (Keycloak enforce)
2. Email mới chưa tồn tại trong `persons.email` (unique constraint, safety net)

**Ảnh hưởng khi đổi:**

| Vùng                  | Ảnh hưởng              | Lý do                                         |
| --------------------- | ---------------------- | --------------------------------------------- |
| Keycloak login        | Không ảnh hưởng        | `keycloak_sub` giữ nguyên                     |
| persons record        | `email` field update   | Auto-sync từ JWT khi login                    |
| B2B contacts          | Không ảnh hưởng        | Linked qua `person_id`, không phải email      |
| B2C account           | Không ảnh hưởng        | Linked qua `person_id`                        |
| Invoice notification  | Tự động dùng email mới | Đọc từ `persons.email`                        |
| Signing link          | Tự động dùng email mới | Đọc từ `persons.email`                        |
| Email đã gửi trước đó | Không recall được      | Chấp nhận — delivery log snapshot tại invoice |

**Audit trail cho email đã gửi:** Lưu `sent_to_email` snapshot tại invoice level — không cần bảng `persons_email_history` riêng.

---

### Payment notification — ping ai

```
Sự kiện                         → Ping ai?
────────────────────────────────────────────────────────────────────
Invoice phát hành (Voorschot)   → INVOICE_RECIPIENT
Direct debit sắp thu tiền       → BILLING_CONTACT
Direct debit thất bại           → BILLING_CONTACT + (leo thang) AUTHORIZED_SIGNATORY
Eindafrekening phát hành        → INVOICE_RECIPIENT + BILLING_CONTACT
Contract sắp hết hạn            → AUTHORIZED_SIGNATORY
```

Notification gửi đến `persons.email` của contact có role tương ứng tại legal entity đó.

---

### SEPA Mandate — snapshot tại contract_versions

IBAN **không** lưu trong `offers` — offer chỉ là pricing proposal, chưa có IBAN tại offer stage.

IBAN được collect trong onboarding (sau khi offer ACCEPTED). Khi đó cần snapshot vào `contract_versions`:

```
contract_versions
  sepa_mandate_id → sepa_mandates.id  // mandate active tại thời điểm ký
```

Khi công ty đổi ngân hàng về sau:

- SEPA mandate cũ: `revoked_at` set, `is_active = false`
- SEPA mandate mới: `is_active = true`
- Payment run tự động dùng mandate mới
- Contract version cũ vẫn trỏ đúng mandate cũ → lịch sử đầy đủ

---

### B2B dual-account case (ông A vừa có B2B vừa có B2C)

```
persons: { id: 99, email: "a@gmail.com", keycloak_sub: "kc-uuid-99" }

contacts:
  { person_id: 99, legal_entity_id: [Ông A cá nhân B2C], role: PRIMARY }
  { person_id: 99, legal_entity_id: [Công ty A B2B],    role: AUTHORIZED_SIGNATORY }

LegalEntity 1: Công ty A (entity_type=ORGANIZATION, kvk=12345678)
  └── Account (B2B) → Contract B2B

LegalEntity 2: Ông A cá nhân (entity_type=INDIVIDUAL)
  └── Account (B2C) → Contract B2C
```

Hai LegalEntity hoàn toàn độc lập, hai luồng billing riêng biệt. Ông A login một lần → context picker hiện cả hai → chọn context tương ứng.

---

## 9.2 Ubiquitous Language: Customer Management

### Thuật ngữ cốt lõi

| Term                    | Định nghĩa                                                                                                                                                                                                               |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Legal Entity**        | Đơn vị pháp lý độc lập — cá nhân hoặc tổ chức — tồn tại trong hệ thống với identity riêng. Một Legal Entity có thể mang nhiều role đồng thời (Customer, Supplier, Partner, Broker...). Không tách riêng theo role.       |
| **Role**                | Vai trò của một Legal Entity trong một context cụ thể. Ví dụ: `customer`, `supplier`, `reseller`, `broker`. Role được gán theo contract/transaction, không phải theo identity.                                           |
| **Account**             | Đơn vị billing và quản lý cho một Legal Entity trong vai trò Customer. Một Legal Entity có thể có nhiều Account (ví dụ: account B2B riêng và account B2C riêng). Account chứa billing configuration và payment settings. |
| **Account Type**        | Phân biệt `B2B` vs `B2C` tại cấp Account — KHÔNG phải tại cấp Legal Entity. Một Legal Entity có thể có cả Account B2B và Account B2C.                                                                                    |
| **Enterprise Group**    | Cấp cao nhất trong B2B hierarchy. Thường là tập đoàn mẹ. Là nơi nhận Consolidated Invoice nếu `billing_entity = true`.                                                                                                   |
| **Subsidiary**          | Công ty con trong B2B hierarchy, thuộc một Enterprise Group. Có thể có nhiều Site.                                                                                                                                       |
| **Site**                | Địa điểm kinh doanh vật lý trong B2B hierarchy, thuộc một Subsidiary. Có cost center tracking. Tương ứng với một Service Location.                                                                                       |
| **Billing Entity**      | Node trong B2B hierarchy được cấu hình là nơi nhận invoice (`billing_entity = true`). Mặc định là cấp Group, nhưng configurable per-account.                                                                             |
| **Cost Center**         | Mã định danh nội bộ của một Site để phân bổ chi phí trong báo cáo tài chính của Enterprise Group.                                                                                                                        |
| **Service Location**    | Địa chỉ vật lý thực tế nơi điện/gas được sử dụng. Phân biệt rõ với: Billing Address (địa chỉ gửi hóa đơn), Legal Address (địa chỉ đăng ký pháp lý). Một Account có thể có nhiều Service Location.                        |
| **Billing Address**     | Địa chỉ nhận invoice. Có thể khác với Service Location address.                                                                                                                                                          |
| **Legal Address**       | Địa chỉ đăng ký pháp lý của Legal Entity. Dùng cho compliance và communication chính thức.                                                                                                                               |
| **KVB (Kleinverbruik)** | Phân khúc tiêu thụ nhỏ. Xác định eligibility cho: Vermindering energiebelasting, Saldering (net-metering). Thường là B2C và SME nhỏ. Được xác định theo EAN và connection capacity.                                      |
| **Verblijfsfunctie**    | Thuộc tính của Service Location: là nơi ở hay không (`true/false`). Cần thiết để xác định eligibility cho Vermindering energiebelasting (chỉ áp dụng khi KVB + Verblijfsfunctie = true).                                 |
| **Hierarchy Depth**     | Độ sâu tối đa của B2B tree: 4 cấp. Quá 4 cấp → cần review cấu trúc tổ chức.                                                                                                                                              |
| **Ownership Transfer**  | Khi B2B restructuring xảy ra, Site chuyển từ Subsidiary này sang Subsidiary khác. Cần track lịch sử ownership với `effective_from/to`. Billing history cũ không bị re-assign.                                            |
