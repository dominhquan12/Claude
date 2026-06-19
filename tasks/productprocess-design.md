# ProductProcess Module — Phân tích & Thiết kế

> Dựa trên: `EdsnController.java`, `EdsnService.java`, `MoveInProductService.java`,
> `SwitchProductService.java`, `ProductProcessService.java`, `ProductProcess.java`,
> `jdl.jdl`, rules `04`, `05`, `08`.
>
> **Xác nhận kiến trúc:**
> - EDSN hoạt động theo mô hình **polling thuần túy** — không có webhook/callback.
>   Mọi endpoint trong `EdsnController` đều là outbound call từ mình tới EDSN.
> - `product_process` (1:1 với `product`) là đúng: một product có một hành trình EDSN
>   duy nhất từ activation đến termination. Move-out xong → product lifecycle kết thúc.
> - **Không cần thêm bảng mới.** `product_process` + `product_process_history` đủ.

---

## 1. Inventory EDSN APIs

### Group 1 — Mutation (chúng ta gửi tới EDSN)

| API | Mô tả | Luồng dùng |
|-----|-------|------------|
| `moveIn` / `moveInBatch` | Kích hoạt supply tại EAN chưa có nhà cung cấp | Move-In |
| `moveOut` / `moveOutBatch` | Kết thúc supply khi customer rời địa chỉ | Move-Out |
| `changeOfSupplier` / `changeOfSupplierBatch` | Chuyển nhà cung cấp | Switch |
| `endOfSupply` / `endOfSupplyBatch` | Kết thúc supply hoàn toàn | Contract terminated |
| `noticeEOS` / `noticeEOSNotification` | Thông báo sắp kết thúc supply | Chuẩn bị end |
| `changeOfPV` / `changeOfPVBatch` | Đăng ký / hủy solar panel | ChangeOfPV |
| `nameChange` | Đổi tên chủ hợp đồng tại metering point | Name change |

### Group 2 — Result polling (chúng ta poll để lấy kết quả)

| API | Ý nghĩa | Kết quả |
|-----|---------|---------|
| `gainResult` | Mình đã gain EAN nào | → `StepType.GAINED` |
| `lossResult` | Mình đã mất EAN nào | → `StepType.LOST` |
| `rejectionResult` | Mutation nào bị reject | → `StepType.REJECTED` |
| `updateResult` | Confirmation cho update mutations | → dùng cho changeOfPV, nameChange |

### Group 3 — Meter data & Master data

| API | Mô tả |
|-----|-------|
| `meterReadingExchange` | Poll meter readings (conventional meter) |
| `p4` / `p4Result` | Smart meter hourly/15-min data |
| `masterDataUpdate` | Poll thay đổi master data từ grid operator |
| `getMeteringPoint` | Lấy chi tiết một EAN |
| `searchMeteringPoints` | Tìm EAN theo địa chỉ |
| `getSCMPInformation` | Ai đang supply EAN này hiện tại |
| `masterData` / `masterDataBatch` | Query master data (captar, capacity) |

---

## 2. Data model

### Quan hệ chính

```
Customer
  └── CustomerOrder  (quotation)
        └── ProductOrder  (service location)
              └── Product  (1 EAN + 1 contract)
                    └── ProductProcess  (1:1 — EDSN journey)
                          └── ProductProcessHistory  (1:many — audit trail)
```

`Product` = kết quả của EAN gắn với contract. Vòng đời:
- `productStatus = NEW` → đang trong quá trình activate
- `productStatus = ACTIVE` → supply đang chạy (sau `GAINED`)
- `productStatus = INACTIVE` → supply đã kết thúc (sau `LOST`)

`ProductProcess` (1:1 với `Product`) track toàn bộ EDSN interaction:
- Activation (MOVE_IN hoặc SWITCH) → `stepType = GAINED`
- Termination (MOVE_OUT) → `stepType = LOST`
- Lịch sử mọi state transition → `ProductProcessHistory`

### State machine — StepType + StepStatus

```
[CREATED + SUCCESS]
    │ cooling off done + desiredDate window ok
    ↓
[ACCEPTED + SUCCESS]
    │ job picks up → gọi EDSN
    ↓
[SENT + PENDING] ──→ API fail → [SENT + RETRY] ──→ (max retry) → [SENT + FAILED]
    │ API ok
    ↓
[SENT + SUCCESS]  ← đang chờ EDSN polling confirm
    │
    ├── PollGainResultJob     → [GAINED + SUCCESS]    (MOVE_IN / SWITCH thành công)
    ├── PollLossResultJob     → [LOST + SUCCESS]      (MOVE_OUT thành công)
    │                                                   hoặc passive SWITCH_OUT
    └── PollRejectionResultJob → [REJECTED + SUCCESS]

[CREATED + SUCCESS] ──→ offerExpirationDate quá hạn → [CANCEL + SUCCESS]
Bất kỳ state ──→ manual cancel by agent → [CANCEL + SUCCESS]
```

**`BLOCKED`:** Hiện có trong enum nhưng chưa có logic — dùng khi cần tạm dừng process
(ví dụ: deposit chưa nhận được, EAN đang có dispute).

**`COMPLETED`:** Có trong enum nhưng không dùng và không có nghĩa rõ ràng.
GAINED/LOST/REJECTED/CANCEL đã là terminal states — COMPLETED thừa. Xem xét xóa.

### Enum ProcessType — thiếu END_OF_SUPPLY

Hiện tại: `MOVE_IN`, `MOVE_OUT`, `SWITCH`.

`MOVE_OUT` và `END_OF_SUPPLY` là hai EDSN API khác nhau:

| | `moveOut` | `endOfSupply` |
|--|-----------|---------------|
| Khi nào | Customer rời địa chỉ vật lý | Contract chấm dứt, không ai tiếp quản |
| EAN sau đó | Vẫn tồn tại, new customer sẽ vào | Có thể bị decommission |
| Cooling-off | Có (theo policy) | Không |
| Ví dụ | Chuyển nhà | Doanh nghiệp đóng cửa, non-payment termination, tòa nhà phá dỡ |

Cả hai đều trả kết quả qua **cùng `lossResult()` polling**, nhưng cần ProcessType riêng vì:
- Phân biệt trong audit trail và reporting
- Policy khác nhau (END_OF_SUPPLY không có desiredDate window)
- Gọi API khác nhau: `edsnService.moveOut()` vs `edsnService.endOfSupply()`

**Cần thêm `END_OF_SUPPLY` vào `ProcessType` enum.**

---

## 3. Vấn đề hiện tại cần fix

### 3.1 transactionId race condition — idempotency risk

Trong `callMoveInApi()` hiện tại:
```
1. persistSendStep()        → save DB với transactionId = null
2. gọi EDSN API
3. setTransactionId(uuid)   → save lại
```

Nếu crash giữa bước 2 và 3: record `SENT+PENDING` với `transactionId = null`.
Lần retry tiếp theo generate UUID mới → **gửi duplicate request lên EDSN cho cùng EAN**.

**Fix:** Generate UUID trước, save cùng record đầu tiên:
```
1. transactionId = UUID.randomUUID()
2. persistSendStep() với transactionId đã có
3. gọi EDSN API với transactionId đó
4. update stepStatus PENDING → SUCCESS/RETRY
```

### 3.2 SENT+SUCCESS không có timeout

Sau khi `callMoveInApi` thành công: `SENT+SUCCESS` = đang chờ EDSN trả kết quả.
Không có cơ chế phát hiện nếu gain result không bao giờ đến.
`product_process` thiếu field `sentAt` để timeout job có thể check.

### 3.3 Retry strategy — giữ manual job-based, không dùng library

**Quyết định: Giữ nguyên cơ chế retry thủ công qua job, không thêm `@Retryable` hay Resilience4j.**

Lý do: EDSN xử lý theo batch, failure thường không phải transient 5-giây.
Khi fail có thể là: EAN không hợp lệ, EDSN bảo trì, ngoài business window.
Retry ngay sau 1 giây không có ý nghĩa.

Job-based retry có lợi thế:
- Crash-safe: server restart vẫn pick up `SENT+RETRY` từ DB
- State visible: ops monitor được, agent can thiệp thủ công được
- Interval phù hợp với tốc độ xử lý của EDSN (phút/giờ)

**Vấn đề thật cần fix:** code hiện tại không phân loại exception:

```java
// Hiện tại — mọi lỗi đều retry giống nhau
catch (Exception e) {
    handleRetry(pp);
}

// Nên sửa thành
catch (EdsnBusinessException e) {
    // EDSN reject rõ ràng (EAN không tồn tại, duplicate request, ngoài window)
    // → không retry, FAILED ngay + lưu reason
    pp.setStepStatus(StepStatus.FAILED);
    pp.setPayloadOut(e.getMessage());
} catch (Exception e) {
    // Network timeout, SOAP fault tạm thời
    // → retry bình thường
    handleRetry(pp);
    pp.setPayloadOut(e.getMessage());
}
```

`EdsnBusinessException` cần tạo mới — parse từ SOAP fault code trong response EDSN.

---

### 3.4 processMoveInAcceptJob không có batch limit — fetch toàn bộ records

`findByProcessStepStatus()` trong `ProductProcessRepositoryCustom` không có `LIMIT` hay `Pageable`.
Khi job chạy, nó fetch **tất cả** records `MOVE_IN + ACCEPTED + SUCCESS` vào memory cùng lúc — không giới hạn.

**Yêu cầu:** Mỗi lần job chạy chỉ xử lý tối đa **15 records** để giảm tải request sang EDSN.
Job chạy lặp lại định kỳ trong khung giờ cuối ngày — nếu có 45 records thì tự nhiên drain qua 3 lần chạy cách nhau theo interval:

```
[TBD: HH:mm] → job chạy → pick 15 → gửi EDSN
[TBD: HH:mm] → job chạy → pick 15 → gửi EDSN
[TBD: HH:mm] → job chạy → pick 15 → gửi EDSN
[TBD: HH:mm] → job chạy → 0 records eligible → no-op
```

Cơ chế hoạt động tự nhiên: sau mỗi lần gửi, records chuyển sang `SENT` → không còn match `ACCEPTED+SUCCESS` → lần chạy tiếp theo pick 15 records tiếp theo.

**Hai trigger gửi moveIn:**

| Trigger | Thời điểm | Batch limit |
|---------|-----------|-------------|
| Manual (`manualMoveIn`) | Ngay lập tức khi agent click | Không áp dụng — gửi 1 record |
| Auto job (`processMoveInAcceptJob`) | Theo cron, cuối ngày | 15 records/lần |

**Cấu hình cần xác định (placeholder):**

| Tham số | Giá trị | Ghi chú |
|---------|---------|---------|
| `BATCH_SIZE` | `15` | Số records tối đa mỗi lần chạy |
| Job window start | `[TBD]` | Giờ bắt đầu chạy job (ví dụ: `20:00`) |
| Job window end | `[TBD]` | Giờ kết thúc (ví dụ: `23:00`) |
| Interval giữa các lần | `[TBD]` | Cron expression (ví dụ: mỗi 15 phút) |

**Fix:**

1. Thêm `Pageable` vào `findByProcessStepStatus()`:

```java
List<ProductProcess> findByProcessStepStatus(
    @Param("processTypes") List<ProcessType> processTypes,
    @Param("stepType") StepType stepType,
    @Param("stepStatuses") List<StepStatus> stepStatuses,
    Pageable pageable
);
```

2. Thêm constant và truyền `PageRequest` vào `processMoveInAcceptJob()` và `processMoveInSendJob()`:

```java
static int BATCH_SIZE = 15;

// trong processMoveInAcceptJob()
productProcessRepository.findByProcessStepStatus(
    List.of(ProcessType.MOVE_IN),
    StepType.ACCEPTED,
    List.of(StepStatus.SUCCESS),
    PageRequest.of(0, BATCH_SIZE)
);
```

3. Cập nhật cron expression của `ProcessMoveInAcceptJob` chạy trong window cuối ngày với interval [TBD].

**Lưu ý:** `SwitchProductService` cũng dùng `findByProcessStepStatus` → cần truyền `Pageable` tương ứng khi sửa.

---

### 3.5 processGainResult() dùng hardcoded data

`getGainResultResponseEnvelopePortaalContent()` trả về JSON hardcoded thay vì gọi
`edsnService.gainResult()` thật. Tương tự `callMoveInApi()` dùng `buildMoveInResponse()`.

### 3.6 Thiếu validation EAN trước khi tạo process

`persistCreateStep()` assume EAN hợp lệ và không có incumbent.
Nếu gửi `moveIn` cho EAN đang có supplier → EDSN reject → chỉ biết khi poll rejectionResult.

Nên validate trước:
```java
SCMPInfo scmp = edsnService.getSCMPInformation(eanId);
ProcessType type = scmp.hasCurrentSupplier() ? SWITCH : MOVE_IN;
```

### 3.7 Post-GAINED chưa làm gì

Sau khi `GAINED`, không:
- Set `product_process.actualStartDate` từ `mutationDate` trong gain response
- Cập nhật `product.productStatus = ACTIVE`
- Trigger billing module bắt đầu voorschot invoice

### 3.8 ProcessType thiếu END_OF_SUPPLY

Khi hợp đồng bị chấm dứt mà customer không chuyển nhà (doanh nghiệp đóng cửa, non-payment, early termination theo yêu cầu): phải gọi `edsnService.endOfSupply()`, không phải `moveOut()`.

Hiện tại không có ProcessType tương ứng → không thể track luồng này trong `product_process`.

**Fix:** Thêm `END_OF_SUPPLY` vào `ProcessType` enum + tạo `EndOfSupplyProductService`.

### 3.9 Passive SWITCH_OUT chưa có xử lý

Khi supplier khác lấy customer của mình (không phải mình initiate):
- EDSN trả về EAN của mình trong `lossResult()`
- **Không có transactionId** để match vì mình không gửi request nào
- Cần match bằng EAN → `Ean` entity → `Product` → `ProductProcess`
- Set `processType = MOVE_OUT`, `stepType = LOST`

`lossResult()` hiện chưa có job xử lý trong productprocess module.

---

## 4. Field cần bổ sung vào `product_process`

Hai field hiện tại đang thiếu trong entity và JDL:

### 4.1 `sentAt` — timestamp khi gọi EDSN

```java
@Column(name = "sent_at")
private Instant sentAt;
```

Set khi `persistSendStep()`. Dùng để:
- Timeout job detect `SENT+SUCCESS` quá lâu không có gain/loss result
- Audit trail chính xác hơn

### 4.2 `actualEndDate` — ngày EDSN confirm kết thúc supply

```java
@Column(name = "actual_end_date")
private LocalDate actualEndDate;
```

Hiện có `actualStartDate` (từ gain result), nhưng thiếu `actualEndDate` (từ loss result).
Khác với `product.inactiveDate` (ngày customer request) —
`actualEndDate` là ngày EDSN confirm effective, lấy từ `mutationDate` trong loss response.
Dùng cho: pro-rata eindafrekening calculation.

### Cập nhật JDL

```jdl
entity ProductProcess {
    // ... fields hiện có ...
    sentAt Instant,           // THÊM MỚI
    actualEndDate LocalDate   // THÊM MỚI
}
```

---

## 5. Job architecture cần implement

| Job | Xử lý | Schedule | Logic |
|-----|-------|----------|-------|
| `ProcessMoveInAcceptJob` | Đã có (disabled) | Cuối ngày, mỗi `[TBD]` phút, trong khung `[TBD]`–`[TBD]` | Pick `MOVE_IN + ACCEPTED+SUCCESS` (limit 15) → gọi `moveIn` → `SENT` |
| `ProcessSwitchAcceptJob` | Đã có (disabled) | `[TBD]` | Pick `SWITCH + ACCEPTED+SUCCESS` (limit 15) → gọi `changeOfSupplier` → `SENT` |
| `ProcessMoveInSendJob` | Đã có (disabled) | `[TBD]` | Retry `MOVE_IN + SENT+PENDING/RETRY` (limit 15) |
| `ProcessSwitchSendJob` | Đã có (disabled) | `[TBD]` | Retry `SWITCH + SENT+PENDING/RETRY` (limit 15) |
| `PollGainResultJob` | Thiếu job, có partial code | `[TBD]` | `gainResult()` → match `transactionId` → `GAINED` + set `actualStartDate` + `product.ACTIVE` |
| `PollLossResultJob` | **Chưa có** | `[TBD]` | `lossResult()` → match `transactionId` hoặc EAN → `LOST` + set `actualEndDate` + `product.INACTIVE` |
| `PollRejectionResultJob` | **Chưa có** | `[TBD]` | `rejectionResult()` → match `transactionId` → `REJECTED` |
| `ExpireProcessJob` | Đã có (disabled) | `[TBD]` | `CREATED+SUCCESS` quá `offerExpirationDate` → `CANCEL` |
| `TimeoutSentJob` | **Chưa có** | `[TBD]` | `SENT+SUCCESS` quá `sentAt + threshold` → alert / escalate |
| `MoveOutAcceptJob` | **Chưa có** | `[TBD]` | Pick `MOVE_OUT + ACCEPTED+SUCCESS` → gọi `moveOut` → `SENT` |
| `EndOfSupplyAcceptJob` | **Chưa có** | `[TBD]` | Pick `END_OF_SUPPLY + ACCEPTED+SUCCESS` → gọi `endOfSupply` → `SENT` |

---

## 6. Luồng đầy đủ

### Move-In (customer mới, EAN chưa có supplier)
```
[Validate]  getSCMPInformation  → confirm chưa có supplier
[Validate]  getMeteringPoint    → EAN hợp lệ
            ↓ persistCreateStep: processType=MOVE_IN, stepType=CREATED
            ↓ mandate signed: stepType=ACCEPTED
[Job]       ProcessMoveInAcceptJob → moveIn() → stepType=SENT, sentAt=now
[Poll]      PollGainResultJob → stepType=GAINED, actualStartDate=mutationDate
                              → product.productStatus=ACTIVE
                              → trigger billing voorschot
[Poll]      PollRejectionResultJob → stepType=REJECTED
```

### Supplier Switch (customer chuyển sang mình từ supplier khác)
```
[Validate]  getSCMPInformation  → lấy incumbent supplier
            ↓ persistCreateStep: processType=SWITCH, stepType=CREATED
            ↓ mandate signed: stepType=ACCEPTED
[Job]       ProcessSwitchAcceptJob → changeOfSupplier() → stepType=SENT, sentAt=now
[Poll]      PollGainResultJob → stepType=GAINED, actualStartDate=mutationDate
                              → product.productStatus=ACTIVE
[Poll]      PollRejectionResultJob → stepType=REJECTED
```

### Move-Out (customer chủ động rời đi)
```
[Trigger]   customer request move-out
            ↓ update processType=MOVE_OUT, stepType=ACCEPTED
[Job]       MoveOutAcceptJob → moveOut() → stepType=SENT, sentAt=now
[Poll]      PollLossResultJob → match transactionId
                              → stepType=LOST, actualEndDate=mutationDate
                              → product.productStatus=INACTIVE
                              → trigger eindafrekening
```

### End of Supply (hợp đồng chấm dứt, không có new supplier)
```
[Trigger]   non-payment termination / customer request cancel / business closure
            ↓ update processType=END_OF_SUPPLY, stepType=ACCEPTED
            ↓ KHÔNG có cooling-off, KHÔNG có desiredDate window
[Job]       EndOfSupplyAcceptJob → endOfSupply() → stepType=SENT, sentAt=now
[Poll]      PollLossResultJob → match transactionId
                              → stepType=LOST, actualEndDate=mutationDate
                              → product.productStatus=INACTIVE
                              → ean.switchingStatus=MOVED_OUT
                              → trigger eindafrekening
```

Khác với MOVE_OUT:
- Không cần `NormalMoveOutPolicy` (không có date window)
- Nên gửi `noticeEOS` trước `endOfSupply` nếu là customer request (thông báo trước)
- Grid operator có thể decommission EAN sau khi LOST

### Passive SWITCH_OUT (supplier khác lấy customer của mình)
```
[Poll]      PollLossResultJob → lossResult() trả về EAN không có transactionId của mình
            ↓ match bằng EAN → Ean → Product → ProductProcess
            ↓ set processType=MOVE_OUT, stepType=LOST, actualEndDate=mutationDate
            → product.productStatus=INACTIVE
            → trigger eindafrekening
```

---

## 7. Side-effect map — cập nhật các bảng theo từng step

Mỗi khi `ProductProcess` chuyển state, các bảng liên quan phải được cập nhật đồng thời.

### Chuỗi liên kết

```
Agreement (1:1) ← CustomerOrder → ProductOrder (1:many) → Product (1:many) → ProductProcess
                                                                └── Ean → Meter
```

- **Agreement.status** = trạng thái contract tổng. Cần check toàn bộ Products trong CustomerOrder trước khi update.
- **ProductOrder.status** = trạng thái location. Cần check toàn bộ Products trong ProductOrder.
- **Ean.switchingStatus** = process đang chạy tại EAN này. Null = không có process in-flight.
- **Meter** = master data từ EDSN. Cập nhật từ `gainResult` và `masterDataUpdate`.

---

### Bảng cập nhật theo từng step

| Step | product | product_order | agreement | ean | meter |
|------|---------|---------------|-----------|-----|-------|
| **CREATED** | — | — | — | `switchingStatus` = MOVE_IN hoặc SWITCH | — |
| **ACCEPTED** | — | — | — | — | — |
| **SENT+SUCCESS** | — | — | — | — | `transactionDossierNumber` = dossier.id từ response |
| **GAINED** | `productStatus` → ACTIVE, `activeDate` = mutationDate | `status` → ACTIVE (nếu ≥1 product ACTIVE) | `status` → ACTIVE, `effectiveDate` = mutationDate | `switchingStatus` → null, `activeMeterNumber` = từ response | `balanceSupplierCompanyId` = our EAN, `startDate` = mutationDate, `energyDeliveryStatus` updated |
| **REJECTED** | `productStatus` giữ nguyên NEW | — | — | `switchingStatus` → null | — |
| **CANCEL / EXPIRED** | `productStatus` → INACTIVE | `status` → INACTIVE (nếu tất cả INACTIVE) | `status` → INACTIVE (nếu tất cả INACTIVE) | `switchingStatus` → null | — |
| **SENT for MOVE_OUT** | — | — | — | `switchingStatus` → MOVE_OUT | — |
| **SENT for END_OF_SUPPLY** | — | — | — | `switchingStatus` → END_OF_SUPPLIER | — |
| **LOST** | `productStatus` → INACTIVE, `inactiveDate` = mutationDate | `status` → INACTIVE (nếu tất cả INACTIVE) | `status` → INACTIVE, `endDate` = mutationDate | `switchingStatus` → MOVED_OUT | `endDate` = mutationDate |
| **masterDataUpdate** (background) | `retrievedYearlyQuantityReading` = standaardJaarAfname | — | — | `isSmartMeter`, `gridArea`, `activeMeterNumber` | Tất cả fields cập nhật từ EDSN |

---

### Chi tiết từng step

#### CREATED
Khi `persistCreateStep()` được gọi:
```
ean.switchingStatus = MOVE_IN        (nếu processType = MOVE_IN)
ean.switchingStatus = SWITCH         (nếu processType = SWITCH)
```
Mục đích: đánh dấu EAN đang có process in-flight, tránh tạo duplicate process.

#### SENT+SUCCESS
Khi `callMoveInApi()` / `callSwitchApi()` thành công:
```
meter.transactionDossierNumber = response.portaalMutation.dossier.id
```
EDSN trả về dossier number ngay khi accept mutation — cần lưu để đối chiếu sau.

#### GAINED
Khi `PollGainResultJob` nhận được result:
```
product.productStatus  = ACTIVE
product.activeDate     = gainResult.mutationDate      ← ngày EDSN confirm, không phải desiredDate

agreement.status       = ACTIVE
agreement.effectiveDate = gainResult.mutationDate

ean.switchingStatus    = null                         ← process hoàn thành, clear
ean.activeMeterNumber  = gainResult.meterNumber       ← nếu có trong response

meter.balanceSupplierCompanyId = our SENDER_ID (8720892404305)
meter.startDate        = gainResult.mutationDate
meter.energyDeliveryStatus = "ACTIVE"                 ← string từ EDSN
```

**Lưu ý Agreement:** Agreement có thể có nhiều Products (electricity + gas bundle).
→ Cần check: nếu ít nhất 1 Product trong CustomerOrder ở trạng thái ACTIVE → Agreement.status = ACTIVE.

#### REJECTED
```
ean.switchingStatus = null    ← process kết thúc (dù fail)
```
Product giữ nguyên `productStatus = NEW`. Agent cần review thủ công.

#### CANCEL / EXPIRED (process hết hạn offer)
```
product.productStatus  = INACTIVE
ean.switchingStatus    = null
```
Nếu tất cả Products trong ProductOrder đều INACTIVE:
```
productOrder.status  = INACTIVE
agreement.status     = INACTIVE
```

#### LOST (MOVE_OUT hoặc passive SWITCH_OUT)
```
product.productStatus  = INACTIVE
product.inactiveDate   = lossResult.mutationDate     ← ngày EDSN confirm, không phải desireEndDate

agreement.status       = INACTIVE
agreement.endDate      = lossResult.mutationDate

ean.switchingStatus    = MOVED_OUT                   ← phân biệt với null (chưa có process nào)

meter.endDate          = lossResult.mutationDate
```

#### masterDataUpdate (job riêng biệt, không liên quan GAINED/LOST)
```
ean.isSmartMeter       = từ EDSN
ean.gridArea           = từ EDSN
ean.activeMeterNumber  = từ EDSN (meter number hiện tại)

product.retrievedYearlyQuantityReading = meter.standaardJaarAfname
    ← cập nhật SJA hàng năm, dùng cho consumption estimate correction

meter.*                = toàn bộ fields cập nhật từ getMeteringPoint / masterDataUpdate response
```

---

### Nguyên tắc quan trọng

1. **Chỉ update bằng data từ EDSN, không dùng desiredDate / desireEndDate**
   `activeDate` ≠ `desiredDate` — EDSN confirm ngày effective thực tế.

2. **Agreement update phải check toàn bộ Products**
   Không set `agreement.status = INACTIVE` chỉ vì một Product LOST nếu còn Product khác ACTIVE.

3. **Ean.switchingStatus = null sau khi GAINED hoặc REJECTED**
   Null = "không có process nào đang chạy tại EAN này". MOVED_OUT = "đã mất EAN hoàn toàn".

4. **Meter fields cập nhật 2 nguồn khác nhau:**
   - `startDate`, `endDate`, `balanceSupplierCompanyId` → từ gain/loss result job
   - Các fields còn lại → từ `masterDataUpdate` job riêng

---

## 8. Checklist implementation

### Phase 0 — Side effects (update bảng liên quan)

- [ ] CREATED: set `ean.switchingStatus = MOVE_IN / SWITCH`
- [ ] SENT+SUCCESS: set `meter.transactionDossierNumber` từ response dossier.id
- [ ] GAINED: set `product.productStatus=ACTIVE`, `product.activeDate=mutationDate`
- [ ] GAINED: set `agreement.status=ACTIVE`, `agreement.effectiveDate=mutationDate` (sau khi check toàn bộ products)
- [ ] GAINED: clear `ean.switchingStatus=null`, update `ean.activeMeterNumber`
- [ ] GAINED: update `meter.balanceSupplierCompanyId`, `meter.startDate`, `meter.energyDeliveryStatus`
- [ ] LOST: set `product.productStatus=INACTIVE`, `product.inactiveDate=mutationDate`
- [ ] LOST: set `agreement.status=INACTIVE`, `agreement.endDate=mutationDate` (sau khi check toàn bộ products)
- [ ] LOST: set `ean.switchingStatus=MOVED_OUT`, `meter.endDate=mutationDate`
- [ ] REJECTED / CANCEL: clear `ean.switchingStatus=null`, set `product.productStatus=INACTIVE`
- [ ] masterDataUpdate job: sync `ean` fields + toàn bộ `meter` fields + `product.retrievedYearlyQuantityReading`

### Phase 1 — Fix & enable flows hiện có

- [ ] Xác nhận job window start/end và interval với team → điền vào `[TBD]` trong section 3.4
- [ ] Thêm `Pageable` vào `findByProcessStepStatus()` trong `ProductProcessRepositoryCustom`
- [ ] Thêm `BATCH_SIZE = 15` constant, truyền `PageRequest.of(0, BATCH_SIZE)` vào `processMoveInAcceptJob()` và `processMoveInSendJob()`
- [ ] Cập nhật cron expression của `ProcessMoveInAcceptJob` theo window + interval đã xác nhận
- [ ] Cập nhật `SwitchProductService` truyền `Pageable` tương ứng khi gọi `findByProcessStepStatus()`
- [ ] Fix `transactionId`: generate UUID trước `persistSendStep()`, không sau
- [ ] Thêm `sentAt` field vào `ProductProcess` entity + JDL + Liquibase migration
- [ ] Thêm `actualEndDate` field vào `ProductProcess` entity + JDL + Liquibase migration
- [ ] Tạo `EdsnBusinessException` — parse từ SOAP fault code trong EDSN response
- [ ] Phân loại exception trong `doSend()`: `EdsnBusinessException` → `FAILED` ngay, `Exception` → `handleRetry()`
- [ ] Wire `edsnService.moveIn()` thật trong `callMoveInApi()` (bỏ hardcoded JSON)
- [ ] Wire `edsnService.changeOfSupplier()` thật trong `callSwitchApi()` (bỏ hardcoded JSON)
- [ ] Wire `edsnService.gainResult()` thật trong `processGainResult()` (bỏ hardcoded JSON)
- [ ] `processGainResult()`: set `actualStartDate` từ `mutationDate` trong response
- [ ] `processGainResult()`: cập nhật `product.productStatus = ACTIVE`
- [ ] Enable các jobs trong `ChangeProductStatusJob` sau khi wire xong

### Phase 2 — Implement missing jobs

- [ ] `PollGainResultJob`: gọi `gainResult()` → match `transactionId` → `GAINED`
- [ ] `PollRejectionResultJob`: gọi `rejectionResult()` → match `transactionId` → `REJECTED`
- [ ] `PollLossResultJob`: gọi `lossResult()`:
  - Match `transactionId` → chủ động MOVE_OUT
  - Không có transactionId → match bằng EAN → passive SWITCH_OUT
  - Set `stepType=LOST`, `actualEndDate=mutationDate`, `product.INACTIVE`
- [ ] `TimeoutSentJob`: `SENT+SUCCESS` quá `sentAt + 7 ngày` → alert

### Phase 3 — Move-Out flow

- [ ] Tạo `MoveOutProductService` (tương tự `MoveInProductService`)
- [ ] Tạo `NormalMoveOutPolicy` (tương tự `NormalMoveInPolicy`)
- [ ] Tạo `MoveOutAcceptJob`: pick `MOVE_OUT + ACCEPTED+SUCCESS` → gọi `moveOut()`
- [ ] Post-LOST: trigger eindafrekening cho billing module

### Phase 3b — End-of-Supply flow

- [ ] Thêm `END_OF_SUPPLY` vào `ProcessType` enum + JDL
- [ ] Tạo `EndOfSupplyProductService` — không có cooling-off, không có date window policy
- [ ] Tạo `EndOfSupplyAcceptJob`: pick `END_OF_SUPPLY + ACCEPTED+SUCCESS` → gọi `endOfSupply()`
- [ ] SENT for END_OF_SUPPLY: set `ean.switchingStatus = END_OF_SUPPLIER`
- [ ] Post-LOST (END_OF_SUPPLY): trigger eindafrekening + notify grid operator nếu EAN decommission
- [ ] Xem xét gọi `noticeEOS` trước `endOfSupply` khi là customer request (advance notice)
- [ ] Xem xét xóa `StepType.COMPLETED` khỏi enum (unused, undefined)

---

## 9. TODO — Phân tích tiếp: Passive SWITCH_OUT full flow

> **Chưa phân tích kỹ — cần làm rõ trước khi implement.**

**Scenario:** Customer đang dùng supply của mình, tự ý đăng ký chuyển sang supplier khác.
Supplier mới gửi `changeOfSupplier` lên EDSN. Mình (incumbent) nhận được kết quả qua `lossResult()` polling — không có cảnh báo trước.

**Các câu hỏi cần phân tích:**

### 9.1 Phát hiện passive SWITCH_OUT
- `lossResult()` trả về EAN với `mutationReason = SWITCH` và không có `transactionId` của mình
- Match EAN → `Ean` → `Product` → `ProductProcess` có `stepType = GAINED` (đang active)
- Tạo mới `ProductProcess` record hay update record hiện tại?
  - Option A: Update record GAINED hiện tại → set `stepType = LOST`
  - Option B: Tạo record mới với `processType = MOVE_OUT`, gắn vào cùng Product
  - **Cần quyết định** — 1:1 relationship không cho phép Option B nếu product cũ vẫn còn

### 9.2 Thông tin cần update sau khi phát hiện
- `product_process`: `stepType = LOST`, `actualEndDate = mutationDate`
- `product`: `productStatus = INACTIVE`, `inactiveDate = mutationDate`
- `agreement`: `status = INACTIVE`, `endDate = mutationDate` (nếu tất cả products INACTIVE)
- `ean`: `switchingStatus = MOVED_OUT`
- `meter`: `endDate = mutationDate`, `balanceSupplierCompanyId = new supplier ID` (từ lossResult)

### 9.3 Customer muốn switch sang supplier mới — flow tiếp theo
Sau khi hệ thống detect passive SWITCH_OUT, customer vẫn trong hệ thống nhưng product đã INACTIVE.
Nếu customer muốn switch trở lại hoặc sang supplier khác:
- Cần tạo `CustomerOrder` mới → `ProductOrder` mới → `Product` mới → `ProductProcess` mới
- EAN cũ vẫn tồn tại trong `Ean` table, dùng lại được
- **Không thể reactivate product cũ** — lifecycle đã kết thúc

### 9.4 Notification khi passive SWITCH_OUT xảy ra
- Cần alert agent/employee ngay khi phát hiện (mất customer không báo trước)
- Cần thông báo customer: "Chúng tôi nhận được thông báo bạn đã chuyển sang supplier khác"
- Trigger eindafrekening cho billing module

### 9.5 Race condition — SWITCH_OUT trong khi đang MOVE_IN
- Nếu mình đang có một MOVE_IN `SENT+SUCCESS` cho EAN X
- Supplier khác cũng submit `changeOfSupplier` cho EAN X cùng lúc
- EDSN có thể reject một trong hai, hoặc confirm theo thứ tự nhận
- `rejectionResult()` sẽ trả về rejection cho request của mình
- Cần xử lý: `REJECTED` → notify agent → investigate

**Ưu tiên implement:** Sau Phase 2 (`PollLossResultJob`) — vì passive SWITCH_OUT được phát hiện trong cùng job đó.

### Phase 4 — Validation trước khi tạo process

- [ ] Gọi `getSCMPInformation` trước `persistCreateStep` → tự detect MOVE_IN vs SWITCH
- [ ] Gọi `getMeteringPoint` để validate EAN hợp lệ trước khi tạo process

### Phase 5 — Post-activation (out of scope productprocess)

- [ ] Billing module: nhận event từ GAINED → bắt đầu voorschot invoice
- [ ] Billing module: nhận event từ LOST → generate eindafrekening
- [ ] Meter reading: poll `meterReadingExchange` sau GAINED (initial reading) và LOST (final reading)
