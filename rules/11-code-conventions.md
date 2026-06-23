# Code Conventions — Crawler Backend

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Java | 21 |
| Framework | Spring Boot 3.4.5 |
| ORM | JPA + Hibernate 6 |
| Migrations | Liquibase |
| Mapping | MapStruct 1.6.3 |
| Validation | Jakarta Validation |
| API Spec | OpenAPI/Swagger (code-generated) |
| Logging | SLF4J + Logstash |

---

## Package Structure

**Base package:** `nl.crawler`

```
src/main/java/nl/crawler/
├── domain/                        ← JPA entities (JHipster-generated, không sửa tay)
├── service/api/dto/               ← API DTOs (OpenAPI-generated, không sửa tay)
└── custom/                        ← Toàn bộ business logic viết tay
    ├── controller/
    ├── service/
    │   └── [feature]/             ← Tổ chức theo domain
    ├── repository/
    ├── mapper/
    ├── model/
    │   ├── internal/              ← Internal DTOs
    │   └── external/              ← External API models
    ├── exception/
    ├── client/
    ├── util/
    └── config/
```

**Quy tắc:** Chỉ viết code trong `nl.crawler.custom`. Không sửa code trong `nl.crawler.domain` và `nl.crawler.service.api.dto` — đây là generated code.

---

## Naming Conventions

| Element | Pattern | Ví dụ |
|---------|---------|-------|
| Controller | `*Controller` | `InvoiceController` |
| Service interface | `*Service` | `InvoiceService` |
| Service implementation | `*ServiceImpl` | `InvoiceServiceImpl` |
| Repository | `*RepositoryCustom` | `InvoiceRepositoryCustom` |
| Mapper | `*Mapper` | `InvoiceMapper` |
| Internal DTO | `*DTO` | `InvoiceDetailDTO` |
| Request/Response | `*Request`, `*Response` | `InvoiceListResponse` |
| Exception | `*Exception` | `BusinessException` |
| Error code | `UPPER_SNAKE_CASE__FEATURE` | `INVOICE_NOT_FOUND__BILLING` |
| Package | lowercase, singular | `nl.crawler.custom.service.invoice` |
| Constant | `UPPER_SNAKE_CASE` | `MAX_RETRY_COUNT` |

---

## Layered Architecture

```
Controller → Service (interface) → ServiceImpl → Repository
                                              ↘ Mapper
```

- Controller chỉ delegate — không chứa business logic
- ServiceImpl chứa toàn bộ business logic
- Repository chỉ data access — không chứa logic

---

## Controller

```java
@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class InvoiceController implements InvoiceApi {

    private final InvoiceService invoiceService;
    private final InvoiceMapper invoiceMapper;

    @Override
    public ResponseEntity<InvoiceListResponse> getInvoiceList(...) {
        return ResponseEntity.ok(invoiceService.getInvoiceList(...));
    }
}
```

**Quy tắc:**
- Implements generated API interface (từ `swagger/api.yml`)
- `@RequiredArgsConstructor` — không dùng `@Autowired`
- Không có `@Transactional`
- Không throw exception trực tiếp — để service xử lý

---

## Service

**Interface:**
```java
public interface InvoiceService {
    InvoiceListResponse getInvoiceList(InvoiceListRequest request);
    void generateInvoice(Long agreementId);
}
```

**Implementation:**
```java
@Service
@RequiredArgsConstructor
@Slf4j
public class InvoiceServiceImpl implements InvoiceService {

    private final InvoiceRepositoryCustom invoiceRepository;
    private final InvoiceMapper invoiceMapper;

    @Override
    @Transactional
    public void generateInvoice(Long agreementId) {
        // business logic
    }

    @Override
    @Transactional(readOnly = true)
    public InvoiceListResponse getInvoiceList(InvoiceListRequest request) {
        // query logic
    }
}
```

**Quy tắc:**
- `@Service` chỉ đặt trên Impl, không đặt trên interface
- `@Transactional` trên method write; `@Transactional(readOnly = true)` trên query
- Dependencies khai báo `private final` tường minh — không dùng `@FieldDefaults`
- `@Slf4j` — dùng `log.debug(...)`, `log.error(...)`, không dùng `System.out.println`

---

## Repository

```java
@Repository
@Primary
public interface InvoiceRepositoryCustom
        extends JpaRepository<Invoice, Long>, JpaSpecificationExecutor<Invoice> {

    Optional<Invoice> findByAgreementId(Long agreementId);

    @Query("SELECT i FROM Invoice i WHERE i.status = :status AND i.dueDate < :date")
    List<Invoice> findOverdueInvoices(@Param("status") InvoiceStatus status,
                                      @Param("date") LocalDate date);
}
```

**Quy tắc:**
- Luôn có suffix `RepositoryCustom`
- `@Repository` + `@Primary`
- Extends `JpaRepository` + `JpaSpecificationExecutor`
- Named parameters dùng `@Param`

---

## DTO

**Internal DTO** — dùng Java record:
```java
@Builder
public record InvoiceDetailDTO(
    Long invoiceId,
    BigDecimal totalAmount,
    LocalDate dueDate
) {}
```

**External/API DTO** — generate từ `swagger/api.yml`, không viết tay.

**Quy tắc:**
- Internal DTO dùng `record` + `@Builder`
- Không tạo class DTO thay thế cho generated DTO — map trực tiếp qua Mapper
- Suffix `DTO` cho internal, `Request`/`Response` cho API layer

---

## Mapper (MapStruct)

```java
@Mapper(
    componentModel = "spring",
    injectionStrategy = InjectionStrategy.CONSTRUCTOR,
    uses = { AgreementMapper.class }
)
public interface InvoiceMapper {

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdDate", expression = "java(Instant.now())")
    Invoice mapToEntity(InvoiceDetailDTO dto);

    InvoiceDetailDTO mapToDTO(Invoice invoice);

    @AfterMapping
    default void postProcess(@MappingTarget InvoiceDetailDTO dto) {
        // post-processing nếu cần
    }
}
```

**Quy tắc:**
- `componentModel = "spring"` + `injectionStrategy = InjectionStrategy.CONSTRUCTOR`
- Không dùng `@Mapper(componentModel = "spring")` thiếu `injectionStrategy`
- `@Mapping(target = "id", ignore = true)` khi map sang entity mới
- Không viết mapping logic tay trong service — luôn dùng Mapper

---

## Optional

**Quy tắc:** Không dùng `isPresent()` + `get()` thô — luôn dùng functional API của Optional.

```java
// SAI — get() không an toàn, compiler không bắt được nếu check bị xóa
if (lastInvoice.isPresent()) {
    current = lastInvoice.get().getEndDate().plusDays(1);
} else {
    current = agreement.getEffectiveDate();
}

// ĐÚNG — có fallback value
LocalDate current = lastInvoice
    .map(inv -> inv.getEndDate().plusDays(1))
    .orElse(agreement.getEffectiveDate());

// ĐÚNG — có fallback value + side effect (log)
LocalDate current = lastInvoice
    .map(inv -> inv.getEndDate().plusDays(1))
    .orElseGet(() -> {
        log.warn("...", agreement.getId(), agreement.getEffectiveDate());
        return agreement.getEffectiveDate();
    });

// ĐÚNG — không có fallback, throw exception
Invoice invoice = invoiceRepository.findById(id)
    .orElseThrow(() -> new BusinessException(HttpStatus.NOT_FOUND,
        ErrorName.INVOICE_NOT_FOUND__BILLING));
```

| Pattern | Dùng khi |
|---------|---------|
| `.map(...).orElse(default)` | Có fallback value đơn giản |
| `.map(...).orElseGet(() -> {...})` | Có fallback + side effect (log, compute) |
| `.orElseThrow(...)` | Không có fallback, missing = lỗi |
| `.ifPresent(...)` | Chỉ cần execute khi present, không cần giá trị trả về |

---

## Exception Handling

**Throw exception trong service:**
```java
Invoice invoice = invoiceRepository.findById(id)
    .orElseThrow(() -> new BusinessException(HttpStatus.NOT_FOUND,
        ErrorName.INVOICE_NOT_FOUND__BILLING));
```

**Thêm error code mới vào `ErrorName` enum:**
```java
// Billing
INVOICE_NOT_FOUND__BILLING,
INVOICE_ALREADY_SENT__BILLING,
```

**Quy tắc:**
- Chỉ dùng `BusinessException` — không throw `RuntimeException` trực tiếp
- Error code format: `WHAT_HAPPENED__FEATURE`
- `GlobalExceptionHandler` xử lý tập trung — không catch exception ở controller

**Khi thêm ErrorName mới — bắt buộc cập nhật 3 chỗ:**

1. `nl.crawler.custom.exception.ErrorName` — thêm enum value
2. `src/main/resources/i18n/messages.properties` — thêm message tiếng Anh
3. `src/main/resources/i18n/messages_nl.properties` — thêm message tiếng Hà Lan
4. Danh sách ErrorName bên dưới trong file này

**Format message hỗ trợ placeholder:**
```properties
# Không có param
INVOICE_NOT_FOUND__BILLING=Invoice not found

# Có param — dùng %s
INVOICE_NOT_FOUND__BILLING=Invoice id = %s not found
```

**Ví dụ throw với param:**
```java
throw new BusinessException(HttpStatus.NOT_FOUND, ErrorName.INVOICE_NOT_FOUND__BILLING, invoiceId);
```

### Danh sách ErrorName hiện tại

> File: `nl.crawler.custom.exception.ErrorName`
> Khi thêm ErrorName mới vào enum, cập nhật danh sách này.

**General:**
```
GENERAL_ERROR
UNSUPPORTED_CUSTOMER_TYPE
MISSING_TEMPLATE
TEMPORARY_DIRECTORY_CREATION_ERROR
DATABASE_CONNECTION_ERROR
DATABASE_ERROR
METHOD_ARGUMENT_TYPE_MISMATCH
FILE_TEMPLATE_NOT_FOUND
PATH_NOT_FOUND
S3_CONNECTION_ERROR
S3_ERROR
METER_NOT_FOUND
```

**1 — Offering (Offer portal):**
```
EAN_SERVICE_NOT_FOUND_ADDRESS__OFFERING
EAN_SERVICE_CLIENT_ERROR__OFFERING
PRODUCT_OFFERING_NOT_FOUND__OFFERING
ESTIMATION_SERVER_ERROR__OFFERING
KVK_UNKNOWN_HTTP_ERROR__OFFERING
KVK_SERVER_ERROR__OFFERING
KVK_NOT_FOUND__OFFERING
IBAN_SERVER_ERROR__OFFERING
IBAN_UNKNOWN_HTTP_ERROR__OFFERING
EMAIL_SEND_ERROR__OFFERING
EMAIL_ATTACHMENT_ERROR__OFFERING
CAPACITY_CODE_NOT_FOUND__OFFERING
LVBAG_UNKNOWN_HTTP_ERROR__OFFERING
LVBAG_SERVER_ERROR__OFFERING
LVBAG_NOT_FOUND__OFFERING
```

**2 — Customer Information (Employee portal):**
```
CUSTOMER_NOT_FOUND__CUSTOMER_INFORMATION
ORGANISATION_NOT_FOUND__CUSTOMER_INFORMATION
EMPLOYEE_NOT_FOUND__CUSTOMER_INFORMATION
CONTACT_NOT_FOUND__CUSTOMER_INFORMATION
SUPPLIER_NOT_FOUND__CUSTOMER_INFORMATION
CUSTOMER_ACCOUNT_NOT_FOUND__CUSTOMER_INFORMATION
BANK_ACCOUNT_NOT_FOUND__CUSTOMER_INFORMATION
ADDRESS_NOT_FOUND__CUSTOMER_INFORMATION
EMAIL_AlREADY_EXISTS__CUSTOMER_INFORMATION
RELATION_CUSTOMER_NOT_FOUND__RELATION_CUSTOMER_INFORMATION
```

**3 — Customer Order (Employee portal):**
```
ORGANISATION_NOT_FOUND__ORGANISATION_MANAGEMENT
CUSTOMER_NOT_FOUND__CUSTOMER_ORDER
CUSTOMER_ACCOUNT_NOT_FOUND__CUSTOMER_ORDER
CONTACT_NOT_FOUND__CUSTOMER_ORDER
CUSTOMER_ORDER_NOT_FOUND__CUSTOMER_ORDER
SUPPLIER_NOT_FOUND__CUSTOMER_ORDER
EMPLOYEE_NOT_FOUND__CUSTOMER_ORDER
KEYCLOAK_USER_NOT_FOUND__CUSTOMER_ORDER
EMPLOYEE_EXISTED__CUSTOMER_ORDER
ROLE_NOT_SUPPORTED__CUSTOMER_ORDER
ROLE_NOT_FOUND__CUSTOMER_ORDER
PRODUCT_PROCESS_ERROR__CUSTOMER_ORDER
```

**4 — Billing (Employee portal):**
```
CUSTOMER_NOT_FOUND__BILLING
AGREEMENT_NOT_FOUND__BILLING
INVOICE_NOT_FOUND__BILLING
TOTAL_LAST_CALC_NOT_FOUND__BILLING
CUSTOMER_ACCOUNT_NOT_FOUND__BILLING
```

**7 — Configuration Management (Employee portal):**
```
DYNAMIC_PRICE_SERVER_ERROR__CONFIGURATION_MANAGEMENT
DYNAMIC_PRICE_UNKNOWN_HTTP_ERROR__CONFIGURATION_MANAGEMENT
DYNAMIC_PRICE_NOT_FOUND__CONFIGURATION_MANAGEMENT
TARIFF_NOT_FOUND__CONFIGURATION_MANAGEMENT
TARIFF_HISTORY_NOT_FOUND__CONFIGURATION_MANAGEMENT
TARIFF_TYPE_NOT_ALLOWED__CONFIGURATION_MANAGEMENT
TARIFF_PRICING_CONSTRAINT_NOT_FOUND__CONFIGURATION_MANAGEMENT
TARIFF_VALUE_BELOW_MIN__CONFIGURATION_MANAGEMENT
TARIFF_VALUE_ABOVE_MAX__CONFIGURATION_MANAGEMENT
TARIFF_TYPE_ID_REQUIRED__CONFIGURATION_MANAGEMENT
TARIFF_VALUE_REQUIRED__CONFIGURATION_MANAGEMENT
EFFECTIVE_DATE_MUST_BE_FUTURE__CONFIGURATION_MANAGEMENT
TARIFF_PRICING_CONSTRAINT_ALREADY_EFFECTIVE__CONFIGURATION_MANAGEMENT
```

**8 — Customer Self Management:**
```
CUSTOMER_NOT_FOUND__CUSTOMER_SELF_MANAGEMENT
```

**9 — Workforce Management:**
```
WORK_ORDER_NOT_FOUND__WORK_ORDER_MANAGEMENT
EMPLOYEE_NOT_FOUND__WORK_ORDER_MANAGEMENT
```

**Task Management:**
```
TASK_NOT_FOUND__TASK_MANAGEMENT
EMPLOYEE_NOT_FOUND__TASK_MANAGEMENT
```

---

## Dependency Injection

```java
// ĐÚNG — constructor injection via Lombok
@RequiredArgsConstructor
public class MyServiceImpl {
    private final InvoiceRepository invoiceRepository;
}

// SAI — field injection
@Autowired
private InvoiceRepository invoiceRepository;
```

---

## Lombok

| Annotation | Dùng khi |
|------------|---------|
| `@RequiredArgsConstructor` | Tất cả Spring components |
| `@Slf4j` | Service, Controller cần logging |
| `@Builder` | DTO record |
| `@Getter`, `@Setter` | JPA Entity |

---

## JPA Entity

```java
@Entity
@Table(name = "invoice")
public class Invoice implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "sequenceGenerator")
    @SequenceGenerator(name = "sequenceGenerator")
    private Long id;

    @NotNull
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private InvoiceStatus status;

    @ManyToOne(fetch = FetchType.LAZY)
    @JsonIgnoreProperties(value = { "invoices" }, allowSetters = true)
    private Agreement agreement;
}
```

**Quy tắc:**
- Import `jakarta.persistence.*` — không dùng `javax.persistence`
- Relationships dùng `FetchType.LAZY` mặc định
- `@JsonIgnoreProperties` để tránh circular reference
- Timestamps dùng `Instant`
- Luôn có `serialVersionUID`

---

## Logging

```java
log.debug("Processing invoice id={}", invoiceId);
log.info("Invoice generated: id={}, amount={}", invoiceId, amount);
log.error("Failed to generate invoice for agreementId={}", agreementId, ex);
```

**Quy tắc:**
- `log.debug` — flow thông thường
- `log.info` — sự kiện quan trọng (invoice created, contract activated...)
- `log.error` — exception có tác động business
- Không log sensitive data (IBAN, BSN, passwords)
- Dùng parameterized logging (`{}`) — không dùng string concatenation

---

## Debuggability

**Quy tắc:** Không return inline expression phức tạp — assign ra biến tại từng bước để debugger có thể inspect giá trị.

**Case 1 — Stream/Optional đơn:**
```java
// SAI
private Optional<EnergyProductUsageDTO> getEnergyProductUsage(...) {
    return estimationUsage.energyProducts().stream()
        .filter(item -> item.productType() == productType)
        .findFirst();
}

// ĐÚNG — inspect result trước khi return
private Optional<EnergyProductUsageDTO> getEnergyProductUsage(...) {
    Optional<EnergyProductUsageDTO> result = estimationUsage.energyProducts().stream()
        .filter(item -> item.productType() == productType)
        .findFirst();
    return result;
}
```

**Case 2 — Multiple flatMap chain (không biết bước nào empty):**
```java
// SAI — không biết flatMap nào trả về empty khi debug
private BigDecimal extractTariffChargesByType(...) {
    return productOffering.getProductOfferingPrices().stream()
        .findFirst()
        .flatMap(price -> price.getTariffs().stream()
            .filter(tariff -> tariffEnum == tariff.getType()).findFirst())
        .flatMap(tariff -> tariff.getTariffHistories().stream()
            .filter(history -> ...)
            .max(Comparator.comparing(TariffHistory::getEffectiveDate))
            .map(history -> BigDecimal.valueOf(history.getTariff())))
        .orElse(BigDecimal.ZERO);
}

// ĐÚNG — đặt breakpoint tại bất kỳ bước nào, inspect từng Optional
private BigDecimal extractTariffChargesByType(...) {
    Optional<ProductOfferingPrice> firstPrice = productOffering
        .getProductOfferingPrices().stream().findFirst();

    Optional<Tariff> matchingTariff = firstPrice
        .flatMap(price -> price.getTariffs().stream()
            .filter(tariff -> tariffEnum == tariff.getType()).findFirst());

    Optional<BigDecimal> tariffValue = matchingTariff
        .flatMap(tariff -> tariff.getTariffHistories().stream()
            .filter(history -> ...)
            .max(Comparator.comparing(TariffHistory::getEffectiveDate))
            .map(history -> BigDecimal.valueOf(history.getTariff())));

    return tariffValue.orElse(BigDecimal.ZERO);
}
```

**Áp dụng khi:** Stream chain, Optional chain có nhiều bước, hoặc multiple flatMap.

**Không áp dụng khi:** Expression đơn giản 1 bước — `return repository.findById(id)` vẫn chấp nhận được.

---

## API Definition

Tất cả endpoints được define trong `src/main/resources/swagger/api.yml`.

**Quy tắc:**
- Thêm endpoint mới → sửa `api.yml` trước, để OpenAPI Generator sinh code
- Không viết `@GetMapping`, `@PostMapping` tay trong Controller — chỉ `@Override` method từ generated interface
- Request/Response DTO → define trong `api.yml`, không tạo class tay
