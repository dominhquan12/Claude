# Plan: Netherlands Household Usage Profile Generator

## Mục tiêu

Thay thế việc đọc file Excel (`hourly-product-usage.xlsx`, `hourly-product-usage-solar.xlsx`) bằng code sinh dữ liệu
trực tiếp trong Java — realistic Netherlands household profiles cho:

- **Electricity consumption** (ELECTRICITY, FeedType.OUT)
- **Solar production** (ELECTRICITY, FeedType.IN)
- **Gas consumption** (GAS, FeedType.OUT)

Granularity: **hourly**, range: **2024-01-01 → now**, timezone: **Europe/Amsterdam** xuyên suốt.

---

## Vấn đề hiện tại cần fix đồng thời

### Bug timezone trong `ImportServiceImpl`

File: `nl.crawler.custom.service.upload.ImportServiceImpl`

```java
// HIỆN TẠI — sai: LocalDateTime không có timezone
LocalDateTime from = LocalDateTime.parse(dto.jhiFrom(), formatter);
ps.setTimestamp(1, Timestamp.valueOf(from));  // JVM timezone implicit → off 1-2h

// FIX — explicit Amsterdam → UTC
Instant fromInstant = from.atZone(BusinessConstants.MARKET_TIMEZONE).toInstant();
ps.setTimestamp(1, Timestamp.from(fromInstant));
```

Fix này áp dụng cho cả `jhi_from` và `util` fields.

---

## Netherlands Household Profiles — Thông số thực tế

### Electricity consumption
- Annual total: ~3.200 kWh/year (CBS Netherlands average household 2024)
- Daily shape:
  - Night (00–06h): baseline thấp ~0.05–0.10 kWh/h
  - Morning peak (07–09h): ~0.35–0.50 kWh/h (khi thức dậy)
  - Midday (10–16h): trung bình ~0.20–0.30 kWh/h
  - Evening peak (17–22h): ~0.40–0.55 kWh/h (nấu ăn, TV, heating)
  - Late night (23h): ramp down
- Seasonal factor: winter ~1.35×, summer ~0.80× — lý do:
  - Mùa đông: ít daylight → đèn nhiều hơn; heating support (heat pump, electric radiator)
  - Mùa hè: nhiều daylight; NL truyền thống ít AC (nhưng đang tăng)
- Weekend: morning peak shift +1h, evening peak ~1.1×

### Solar production
- Annual total: ~3.500 kWh/year (average 10–14 panel NL installation, ~4.5 kWp)
- Chỉ produce ban ngày — zero từ sunset đến sunrise

**Sunrise/Sunset tại Amsterdam (52.37°N) — chênh lệch cực lớn giữa mùa:**

| Mốc | Sunrise | Sunset | Daylight hours |
|-----|---------|--------|----------------|
| Jun 21 (hè) | 05:19 | 22:01 | **16.7h** |
| Sep 21 (thu) | 07:30 | 19:45 | ~12.2h |
| Dec 21 (đông) | 08:47 | 16:29 | **7.7h** |
| Mar 21 (xuân) | 06:20 | 18:30 | ~12.2h |

→ Số giờ có solar gấp đôi giữa hè và đông — đây là yếu tố lớn nhất.

**Solar noon shift do DST:**
- Mùa đông (CET, UTC+1): solar noon ≈ 12:40 Amsterdam
- Mùa hè (CEST, UTC+2): solar noon ≈ 13:40 Amsterdam
- Chênh 1 giờ → bell curve peak phải shift theo

**Monthly kWh distribution (target tổng = 3.500 kWh, scale factor = 3500/2840 ≈ 1.232):**

| Tháng | kWh (raw) | kWh (scaled) | Tháng | kWh (raw) | kWh (scaled) |
|-------|-----------|--------------|-------|-----------|--------------|
| Jan | 55 | 68 | Jul | 430 | 530 |
| Feb | 100 | 123 | Aug | 370 | 456 |
| Mar | 220 | 271 | Sep | 250 | 308 |
| Apr | 330 | 407 | Oct | 140 | 172 |
| May | 400 | 493 | Nov | 70 | 86 |
| Jun | 430 | 530 | Dec | 45 | 55 |
| | | | **Total** | **2.840** | **~3.500** |

**Overcast factor (cloud factor = actual sunshine / max possible sunshine):**

NL sunshine hours thực tế vs max possible per month (52.37°N):

| Tháng | Actual (h) | Max possible (h) | **Cloud factor** |
|-------|-----------|------------------|------------------|
| Jan | 60 | 240 | **0.25** |
| Feb | 90 | 280 | **0.32** |
| Mar | 130 | 370 | **0.35** |
| Apr | 175 | 440 | **0.40** |
| May | 210 | 510 | **0.41** |
| Jun | 210 | 540 | **0.39** |
| Jul | 205 | 530 | **0.39** |
| Aug | 195 | 470 | **0.41** |
| Sep | 155 | 380 | **0.41** |
| Oct | 105 | 290 | **0.36** |
| Nov | 65 | 220 | **0.30** |
| Dec | 50 | 200 | **0.25** |

> Lưu ý: Jun và Mar có cloud factor gần bằng nhau (~0.39 vs 0.35).
> Jun produce nhiều hơn vì **có nhiều giờ daylight hơn**, không phải vì ít mây hơn.
> Plan cũ dùng Jun=0.55 là sai — nhầm lẫn giữa absolute output và cloud factor.

### Gas consumption
- Annual total: ~1.500 m³/year (CBS Netherlands average household 2024)
- Highly seasonal: winter chiếm ~70% annual usage
  - January/February: ~180–200 m³/month
  - June/July/August: ~20–30 m³/month (chỉ warm water)
- Daily shape (heating season):
  - Morning (06–09h): ramp up heating ~0.08–0.15 m³/h
  - Midday (12–13h): lunch cooking spike
  - Evening (17–21h): dinner + heating peak ~0.12–0.18 m³/h
  - Night: near zero
- Summer daily shape: flat baseline ~0.02 m³/h (hot water only)

---

## Kiến trúc solution

### Các class cần tạo

```
nl.crawler.custom.service.fakedata/
├── FakeDataService.java              ← sửa: bỏ Excel, dùng generator
└── profile/
    ├── UsageProfileGenerator.java    ← orchestrator, entry point
    ├── ElectricityProfileGenerator.java
    ├── SolarProfileGenerator.java
    └── GasProfileGenerator.java
```

### Interface chung

```java
// Mỗi generator implement interface này
public interface ProfileGenerator {
    List<HourlyProductUsageExcelDto> generate(Long productId, LocalDate from, LocalDate toExclusive);
}
```

---

## Chi tiết từng generator

### 1. `ElectricityProfileGenerator`

Input: `productId`, `from`, `toExclusive`

Logic:
```
For mỗi giờ trong range (Amsterdam timezone):
    base = hourlyShape[hour]           // 24-element array, normalized
    seasonal = seasonalFactor(month)   // winter cao hơn
    weekend = weekendFactor(dayOfWeek, hour)
    noise = 1 + random(-0.05, 0.05)   // ±5% noise tự nhiên

    kWh = base × seasonal × weekend × noise × ANNUAL_TARGET / HOURS_IN_YEAR
```

Constant:
```
ANNUAL_TARGET = 3200.0  // kWh
```

Hourly shape array (normalized, sum = 24):
```
index  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
value .5 .4 .4 .4 .4 .5 .8 1.8 1.9 1.2 1.0 .9 .9 .9 .9 1.0 1.2 1.8 2.0 2.0 1.8 1.5 1.0 .7
```

Seasonal factor per month:
```
Jan=1.35, Feb=1.30, Mar=1.15, Apr=1.00, May=0.90, Jun=0.80,
Jul=0.80, Aug=0.82, Sep=0.90, Oct=1.05, Nov=1.20, Dec=1.38
```

### 2. `SolarProfileGenerator`

Input: `productId`, `from`, `toExclusive`

Logic:
```
For mỗi giờ trong range (Amsterdam timezone):
    solarElevation = computeElevation(date, hour, lat=52.37, lon=4.90)
    if solarElevation <= 0: production = 0.0
    else:
        rawProduction = sin(elevation_rad) × peakCapacity
        cloudFactor = monthlyCloudFactor(month)   // NL cloud coverage
        production = rawProduction × cloudFactor × noise
```

`computeElevation` dùng công thức solar declination + hour angle — không cần external lib,
có thể tính approximate bằng:
```
declination = 23.45 × sin(360/365 × (dayOfYear - 81))
hourAngle = (solarHour - 12) × 15
elevation = arcsin(sin(lat) × sin(dec) + cos(lat) × cos(dec) × cos(hourAngle))
```

Cloud factor (actual sunshine / max possible — xem bảng ở trên):
```
Jan=0.25, Feb=0.32, Mar=0.35, Apr=0.40, May=0.41, Jun=0.39,
Jul=0.39, Aug=0.41, Sep=0.41, Oct=0.36, Nov=0.30, Dec=0.25
```

Solar noon per season (để shift bell curve đúng):
```
Đông (Nov–Feb, CET  UTC+1): solarNoonHour = 12  (peak tại giờ 12 Amsterdam)
Hè   (Apr–Sep, CEST UTC+2): solarNoonHour = 13  (peak tại giờ 13 Amsterdam)
Chuyển tiếp (Mar, Oct):     solarNoonHour = 12 hoặc 13 (tùy DST transition date)
```

DST 2024: spring forward Mar 31, fall back Oct 27.
DST 2025: spring forward Mar 30, fall back Oct 26.
→ Code phải check `ZonedDateTime.getOffset()` tại thời điểm đó, không hardcode.

Scale factor: sau khi generate raw (với cloud factor + elevation formula),
tính `sum(raw)` rồi nhân `ANNUAL_TARGET / sum(raw)` để đảm bảo tổng = 3.500 kWh.

### 3. `GasProfileGenerator`

Input: `productId`, `from`, `toExclusive`

Logic:
```
For mỗi giờ trong range (Amsterdam timezone):
    seasonalBase = monthlyGasBase(month)    // m³/month
    hourlyBase = seasonalBase / daysInMonth / 24
    shape = hourlyGasShape[hour]            // heating pattern
    noise = 1 + random(-0.08, 0.08)
    m3 = hourlyBase × shape × noise
```

Monthly gas usage (m³), scale factor = 1500/1247 ≈ **1.203**:

```
Jan=195, Feb=180, Mar=145, Apr=100, May=60,  Jun=25,
Jul=20,  Aug=22,  Sep=55,  Oct=105, Nov=150, Dec=190
→ raw tổng = 1.247 m³ × 1.203 = 1.500 m³ target
```

Context tại sao seasonal gap lớn:
- Mùa đông: space heating chiếm ~75% gas usage
- Mùa hè (Jun–Aug): chỉ domestic hot water → ~20–25 m³/month flat
- Heating season: October → April (7 tháng)

Hourly shape (heating season):
```
index  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
value .3 .2 .2 .2 .2 .3 .8 1.8 1.5 .8 .7 .8 1.2 .8 .7 .8 1.0 1.6 1.8 1.7 1.3 .9 .6 .4
```

---

## Noise strategy

Seed **per hour slot**, không phải per product:

```java
// Tính noise cho một giờ cụ thể — stable mọi lúc, bất kể range import
private double noise(long productId, int year, int dayOfYear, int hour, double amplitude) {
    long slotSeed = productId * 2_654_435_761L  // large prime → spread sequential productId
                  + year      * 8_784L           // max hours in leap year → no year collision
                  + dayOfYear * 24L
                  + hour;
    double rand = new Random(slotSeed).nextDouble(); // 0.0 → 1.0
    return 1.0 + (rand * 2 - 1) * amplitude;        // 1 ± amplitude
}

// Dùng trong generator:
double noise = noise(productId, year, dayOfYear, hour, 0.05);  // ±5% electricity
double noise = noise(productId, year, dayOfYear, hour, 0.08);  // ±8% gas
```

Tại sao KHÔNG dùng `new Random(productId)` reset mỗi lần gọi:
- Range extend → re-import → noise của giờ cũ ra giá trị khác → `ON CONFLICT DO UPDATE` overwrite data cũ bằng noise mới
- `new Random(1)`, `new Random(2)`, `new Random(3)` cho sequence gần giống nhau ở các call đầu → các product trông correlated bất thường

---

## Tích hợp vào `FakeDataService`

`ProductImportTask` mở rộng thêm `profileType` và `startDate`:
```java
public record ProductImportTask(Long productId, ProfileType profileType, LocalDate startDate) {
    public enum ProfileType { ELECTRICITY, SOLAR, GAS }
}
```

`startDate` = `customerOrder.getDesiredDate()` — ngày supply bắt đầu theo contract.
`to` = `LocalDate.now(clock).plusDays(1)` — đến hiện tại.

```java
// TRƯỚC (Excel, không có date range)
MultipartFile file = loadAsMultipartFile("config/data/hourly-product-usage.xlsx");
List<HourlyProductUsageExcelDto> dtos = HourlyProductUsageExcelParser.parse(file)
    .stream().map(dto -> dto.withProductId(task.productId())).toList();

// SAU (generator, date range từ desiredDate → now)
LocalDate to = LocalDate.now(clock).plusDays(1);
List<HourlyProductUsageExcelDto> dtos = switch (task.profileType()) {
    case ELECTRICITY -> electricityGenerator.generate(task.productId(), task.startDate(), to);
    case SOLAR       -> solarGenerator.generate(task.productId(), task.startDate(), to);
    case GAS         -> gasGenerator.generate(task.productId(), task.startDate(), to);
};
```

### Thay đổi trong `OfferServiceImpl`

Hiện tại:
```java
// OfferServiceImpl.java:184
importHourlyProductUsage(productOrders);

private void importHourlyProductUsage(Set<ProductOrder> productOrders) {
    List<FakeDataService.ProductImportTask> importTasks = productOrders
        .stream()
        .flatMap(po -> po.getProducts().stream())
        .map(p -> new FakeDataService.ProductImportTask(
            p.getId(),
            p.getFeedInType() == FeedInType.SOLAR
        ))
        .toList();
    fakeDataService.importHourlyProductUsage(importTasks);
}
```

Sau khi sửa — truyền thêm `customerOrder`:
```java
// OfferServiceImpl.java:184
importHourlyProductUsage(customerOrder, productOrders);

private void importHourlyProductUsage(CustomerOrder customerOrder, Set<ProductOrder> productOrders) {
    LocalDate startDate = customerOrder.getDesiredDate();  // supply start date từ contract

    List<FakeDataService.ProductImportTask> importTasks = productOrders
        .stream()
        .flatMap(po -> po.getProducts().stream())
        .map(p -> new FakeDataService.ProductImportTask(
            p.getId(),
            resolveProfileType(p),
            startDate
        ))
        .toList();
    fakeDataService.importHourlyProductUsage(importTasks);
}

private FakeDataService.ProductImportTask.ProfileType resolveProfileType(Product p) {
    if (p.getProductType() == ProductType.GAS) return ProfileType.GAS;
    if (p.getFeedInType() == FeedInType.SOLAR) return ProfileType.SOLAR;
    return ProfileType.ELECTRICITY;
}
```

---

## Timestamp convention — quan trọng

Tất cả generator phải produce timestamps theo đúng convention:

```java
// Mỗi hourly record
Instant from = localDate.atTime(hour, 0).atZone(BusinessConstants.MARKET_TIMEZONE).toInstant();
Instant to   = localDate.atTime(hour, 0).plusHours(1).atZone(BusinessConstants.MARKET_TIMEZONE).toInstant();

// Lưu vào DTO dạng ISO string (ImportServiceImpl sẽ parse lại)
jhiFrom = from.toString()   // "2024-01-01T23:00:00Z"
jhiTo   = to.toString()     // "2024-01-02T00:00:00Z"
```

`ImportServiceImpl` sau khi fix sẽ parse bằng `Instant.parse()` thay vì `LocalDateTime.parse()`:
```java
// FIX ImportServiceImpl
Instant from = Instant.parse(dto.jhiFrom());
Instant to   = Instant.parse(dto.jhiTo());
ps.setTimestamp(1, Timestamp.from(from));
ps.setTimestamp(2, Timestamp.from(to));
```

---

## DST Transition Hours

Hai giờ đặc biệt mỗi năm tại `Europe/Amsterdam` phải xử lý đúng.

### Spring forward — giờ không tồn tại

Mar 30 2025 02:00 CET → nhảy thành 03:00 CEST.
Giờ `02:00–03:00 Amsterdam` **không tồn tại** → không được generate record.

```java
// Khi iterate qua các giờ Amsterdam, dùng ZonedDateTime để detect
ZonedDateTime zdt = localDate.atTime(hour, 0)
    .atZone(BusinessConstants.MARKET_TIMEZONE);

if (zdt.getHour() != hour) {
    // DST gap: giờ này không tồn tại, skip
    continue;
}
```

Lý do `getHour() != hour`: khi `atTime(2, 0).atZone(Amsterdam)` vào ngày spring forward,
ZonedDateTime tự adjust thành 03:00 → `getHour()` trả về 3, không phải 2 → detect được gap.

### Fall back — giờ xuất hiện 2 lần

Oct 26 2025 03:00 CEST → quay lại 02:00 CET.
Giờ `02:00–03:00` xuất hiện **2 lần**: lần đầu offset +02:00, lần hai offset +01:00.
Phải generate **2 records riêng biệt** với UTC timestamp khác nhau.

```java
// Với giờ bình thường: chỉ có 1 offset → 1 record
// Với giờ fall back: có 2 offset → 2 records

ZoneId ams = BusinessConstants.MARKET_TIMEZONE;
ZoneRules rules = ams.getRules();
LocalDateTime ldt = localDate.atTime(hour, 0);
List<ZoneOffset> validOffsets = rules.getValidOffsets(ldt);

for (ZoneOffset offset : validOffsets) {
    // validOffsets.size() == 1: giờ bình thường
    // validOffsets.size() == 2: fall back — generate cả 2
    Instant slotFrom = ldt.toInstant(offset);
    Instant slotTo   = ldt.plusHours(1).toInstant(offset);
    result.add(buildDto(productId, slotFrom, slotTo, computeValue(...)));
}
```

### DST dates cần xử lý (2024–2026)

| Năm | Spring forward | Fall back |
|-----|---------------|-----------|
| 2024 | Mar 31 | Oct 27 |
| 2025 | Mar 30 | Oct 26 |
| 2026 | Mar 29 | Oct 25 |

Code dùng `ZoneRules.getValidOffsets()` → tự handle mọi năm, không hardcode dates.

---

## Net Metering Effect (Electricity consumption)

Household có solar sẽ dùng solar production trực tiếp trước khi lấy từ lưới.
`ElectricityProfileGenerator` phải nhận solar production của cùng giờ để tính `grid_consumption`.

### Logic

```
gross_consumption = hourlyShape × seasonal × noise   // nhu cầu thực tế của nhà
solar_production  = SolarProfileGenerator.generate() // lượng solar giờ đó

grid_consumption  = max(0.0, gross_consumption - solar_production)
```

### Implication cho generator

`ElectricityProfileGenerator` cần biết product có solar hay không:

```java
// Interface không đổi
List<HourlyProductUsageExcelDto> generate(Long productId, LocalDate from, LocalDate to);

// Nhưng ElectricityProfileGenerator cần thêm optional solar data
@Component
public class ElectricityProfileGenerator implements ProfileGenerator {

    private final SolarProfileGenerator solarGenerator;

    // Khi gọi cho household có solar:
    public List<HourlyProductUsageExcelDto> generateWithSolar(
            Long electricityProductId,
            Long solarProductId,
            LocalDate from,
            LocalDate to) {

        // Generate solar trước
        Map<Instant, Double> solarBySlot = solarGenerator
            .generate(solarProductId, from, to)
            .stream()
            .collect(toMap(dto -> Instant.parse(dto.jhiFrom()), HourlyProductUsageExcelDto::hourlyUsage));

        // Generate electricity, trừ solar tại mỗi slot
        return generateHours(from, to, (slot, gross) -> {
            double solar = solarBySlot.getOrDefault(slot, 0.0);
            return Math.max(0.0, gross - solar);
        });
    }
}
```

### Thay đổi trong `OfferServiceImpl`

`ProductImportTask` cần biết `solarProductId` của cùng `ProductOrder` (nếu có):

```java
private void importHourlyProductUsage(CustomerOrder customerOrder, Set<ProductOrder> productOrders) {
    LocalDate startDate = customerOrder.getDesiredDate();

    productOrders.forEach(po -> {
        // Tìm solar product trong cùng ProductOrder (nếu có)
        Long solarProductId = po.getProducts().stream()
            .filter(p -> p.getFeedInType() == FeedInType.SOLAR)
            .map(Product::getId)
            .findFirst()
            .orElse(null);

        po.getProducts().forEach(p -> {
            ProfileType type = resolveProfileType(p);
            var task = new FakeDataService.ProductImportTask(
                p.getId(), type, startDate, solarProductId
            );
            fakeDataService.importHourlyProductUsage(List.of(task));
        });
    });
}
```

`ProductImportTask` thêm `solarProductId`:
```java
public record ProductImportTask(
    Long productId,
    ProfileType profileType,
    LocalDate startDate,
    Long solarProductId    // null nếu không có solar
) {}
```

---

## Thứ tự thực hiện

1. **Fix `ImportServiceImpl`** — timezone bug, đổi sang `Instant.parse()` + `Timestamp.from()`
2. **Tạo `UsageProfileGenerator` interface**
3. **Implement `SolarProfileGenerator`** — cần trước vì Electricity phụ thuộc vào
4. **Implement `ElectricityProfileGenerator`** — có DST handling + net metering
5. **Implement `GasProfileGenerator`** — có DST handling
6. **Sửa `FakeDataService` + `OfferServiceImpl`** — bỏ Excel, truyền `solarProductId`
7. **Xoá các file Excel** không còn dùng:
   - `config/data/hourly-product-usage.xlsx`
   - `config/data/hourly-product-usage-solar.xlsx`

---

## Files bị ảnh hưởng

| File | Thay đổi |
|------|----------|
| `ImportServiceImpl.java` | Fix timezone bug: `LocalDateTime` → `Instant` |
| `FakeDataService.java` | Bỏ Excel, inject generators, mở rộng `ProductImportTask` |
| `OfferServiceImpl.java` | Truyền `customerOrder` + `solarProductId` vào task |
| `HourlyProductUsageExcelDto.java` | Không đổi — giữ nguyên làm DTO trung gian |
| `HourlyProductUsageExcelParser.java` | Không dùng nữa — giữ lại nếu còn endpoint upload |
| *(new)* `profile/ProfileGenerator.java` | Interface |
| *(new)* `profile/ElectricityProfileGenerator.java` | Impl — DST + net metering |
| *(new)* `profile/SolarProfileGenerator.java` | Impl — DST aware |
| *(new)* `profile/GasProfileGenerator.java` | Impl — DST aware |
| `config/data/hourly-product-usage.xlsx` | Xoá |
| `config/data/hourly-product-usage-solar.xlsx` | Xoá |
