# Bounded Context: Payment

## 2.12 Payment

Payment:

- Direct debit
- Bank transfer
- Failed payment
- Partial payment

Cần:

- Payment reconciliation
- Outstanding balance

---

## 7.7 Multi-currency

**Hiện tại:** Thị trường Hà Lan → chỉ **EUR**.

| Scenario                           | Cần multi-currency?                          |
| ---------------------------------- | -------------------------------------------- |
| Chỉ thị trường NL                  | Không                                        |
| Expand sang BE, DE, FR             | Có                                           |
| B2B invoice cho công ty nước ngoài | Có thể (invoice vẫn EUR, nhưng FX reporting) |

**Quyết định:** Thiết kế để `currency_code` là configurable field ngay từ đầu, nhưng **default và enforce EUR** cho NL market. Không hardcode "EUR" vào business logic.

---

## 9.8 Ubiquitous Language: Payment

### Thuật ngữ cốt lõi

| Term                                    | Định nghĩa                                                                                                                                                     |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Direct Debit (Automatische Incasso)** | Phương thức thanh toán mặc định: hệ thống tự động thu tiền từ tài khoản ngân hàng của Customer theo lịch. Phổ biến nhất tại Hà Lan.            |
| **IBAN**                                | Số tài khoản ngân hàng quốc tế. Dùng để setup Direct Debit mandate.                                                                            |
| **SEPA Mandate**                        | Ủy quyền của Customer cho phép Supplier thu tiền qua SEPA Direct Debit. Phải được lưu và track validity.                                       |
| **Payment Run**                         | Batch process thực hiện thu tiền cho tất cả invoices đến hạn. Thường chạy định kỳ (ví dụ: ngày 1 hàng tháng).                                  |
| **Payment Due Date**                    | Ngày Customer phải thanh toán Invoice. Thường là một số ngày sau Invoice Date (ví dụ: Net 14 hoặc Net 30).                                     |
| **Payment Reconciliation**              | Quá trình đối chiếu giữa tiền đã nhận (bank statement) và Invoice outstanding. Cần match Payment với Invoice chính xác.                        |
| **Failed Payment**                      | Direct Debit bị reject do: insufficient funds, invalid IBAN, mandate revoked. Trigger: reminder, retry, và nếu liên tục → Contract Suspension. |
| **Partial Payment**                     | Customer thanh toán ít hơn outstanding amount. Cần track outstanding balance còn lại.                                                          |
| **Outstanding Balance**                 | Tổng số tiền Customer còn nợ tại một thời điểm: tổng unpaid invoices + debit notes − credit notes − payments.                                  |
| **Bank Transfer**                       | Phương thức thanh toán thay thế — Customer chủ động chuyển khoản. Cần track đến khi tiền thực sự vào tài khoản và reconcile với Invoice.       |
| **Refund**                              | Trả lại tiền cho Customer khi Outstanding Balance âm (Customer trả thừa). Thường qua bank transfer ra IBAN của Customer.                       |
