# Regulatory Compliance — Dutch Energy Market

## 7.8 Regulatory Compliance

### GDPR

- Customer consumption data là personal data → cần retention policy.
- Smart meter data granularity < 15 phút cần explicit consent.
- Right to erasure phức tạp: consumption history liên quan đến billing (legal obligation giữ lại).
- **Implication:** Phân biệt `personal_data` fields (có thể xóa) và `billing_data` fields (bắt buộc giữ).

### ACM (Autoriteit Consument & Markt) — Energy Regulator

- Quy định switching timeline: 31 ngày.
- Price transparency: customer phải thấy rõ từng component của giá.
- Estimated billing: không được estimate quá 12 tháng liên tiếp.

### Energiebelasting (EB) & ODE

- EB có consumption tiers — giảm dần khi consumption tăng.
- ODE thay đổi hàng năm theo quyết định chính phủ.
- **Implication:** Tax rate phải versioned giống tariff — không hardcode.

### P4 Metering & EDSN

- Grid operators dùng P4 protocol cho metering data exchange.
- Supplier nhận meter data qua EDSN portal/API — không tự collect.
- **Implication:** Cần integration layer với EDSN.

### Supplier License

- Supplier phải có ACM license để hoạt động.
- Hệ thống cần track license validity của supplier.
