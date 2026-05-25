# Bounded Context: Supplier Management & Switching

## 3.2 Supplier Switching Flow

Rất đặc thù ngành năng lượng.

Timeline (Hà Lan):

```
Day 0:  Customer yêu cầu switch sang Supplier B
Day 1:  Supplier B gửi switch request lên grid operator
Day 7:  Grid operator confirm (hoặc reject)
Day 30: Effective switch date (thường đầu tháng tiếp theo)
        - Final meter reading được ghi lại
        - Supplier A generate settlement invoice
        - Supplier B bắt đầu billing
```

Lưu ý: Trong thời gian switching có thể tồn tại hai contract active chồng nhau tại cùng supply point.

---

## 7.2 Supplier Switching — Chi tiết EDI/Message Flow

Ở Hà Lan, supplier switching vận hành qua **EDSN** (Energy Data Services Netherlands) và dùng EDIFACT/XML messages.

**Flow chi tiết:**

```
Customer           Supplier B          EDSN/Grid Operator      Supplier A
    │                  │                       │                    │
    │── request ──────▶│                       │                    │
    │                  │── C4/SwitchRequest ──▶│                    │
    │                  │                       │── validate EAN     │
    │                  │                       │── check incumbent ─▶
    │                  │◀── C4/Confirm ────────│                    │
    │◀── confirm ──────│                       │── notify ──────────▶
    │                  │                       │                    │── acknowledge
    │                  │                       │                    │
    │             [30 days later — effective date]                   │
    │                  │                       │── final reading ───▶
    │                  │                       │◀── reading data ───│
    │                  │◀── E01/MeterData ─────│                    │
    │                  │   (final reading)     │                    │
    │                  │                       │                    │
    │           Supplier B starts billing      │  Supplier A gen    │
    │                  │                       │  settlement invoice│
```

**Các trường hợp edge:**

1. **Grid operator reject switch:** EAN không hợp lệ, đang trong contract period có penalty, hoặc đang có switch request khác pending.
2. **Final reading missing:** Nếu smart meter không gửi được final reading → cả hai supplier dùng estimated reading, sau này reconcile khi có actual.
3. **Backdated switch:** Grid operator xử lý chậm → effective date bị lùi → billing period của cả hai supplier phải adjust.
4. **Double supply:** Lỗi hệ thống khiến cả hai supplier cùng billing → cần dispute resolution process.

**Implication:**

- Cần track trạng thái switching request: `Pending → Confirmed → Rejected → Completed`.
- Hệ thống phải nhận và xử lý EDIFACT messages từ EDSN.
- Billing Supplier B không được start cho đến khi nhận `final reading confirmed`.

---

## 9.7 Ubiquitous Language: Supplier Management

### Thuật ngữ cốt lõi

| Term                                     | Định nghĩa                                                                                                                                                                                        |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Supplier**                             | Một Legal Entity trong role `supplier` — bên cung cấp năng lượng có license từ ACM.                                                                                                               |
| **ACM License**                          | Giấy phép hoạt động cung cấp điện/gas tại Hà Lan do Autoriteit Consument & Markt cấp. Hệ thống phải track validity.                                                                               |
| **License Validity**                     | Khoảng thời gian ACM License còn hiệu lực. Supplier có License expired không được nhận Contract mới.                                                                                              |
| **Supplier Switching Request**           | Yêu cầu chuyển từ Supplier hiện tại (Incumbent) sang Supplier mới (New Supplier). Được gửi đến EDSN và phải được grid operator confirm. Trạng thái: `Pending → Confirmed / Rejected → Completed`. |
| **Incumbent Supplier**                   | Supplier đang active tại một EAN tại thời điểm switch request được gửi.                                                                                                                           |
| **New Supplier**                         | Supplier được Customer chọn để switch đến. Phải có ACM License hợp lệ.                                                                                                                            |
| **Switch Effective Date**                | Ngày chính thức Supplier mới bắt đầu supply tại EAN. Thường là đầu tháng tiếp theo sau khi grid operator confirm (tối thiểu 31 ngày theo quy định ACM).                                           |
| **EDSN Integration**                     | Kết nối với hệ thống EDSN để: submit switch requests, nhận meter data, receive confirmation/rejection messages. Dùng EDIFACT/XML messages theo P4 protocol.                                       |
| **Settlement Invoice (Supplier Switch)** | Eindafrekening được Incumbent Supplier generate khi mất một Customer do switching. Cover period từ billing start đến Switch Effective Date.                                                       |
