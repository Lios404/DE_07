# Glamira dbt Project — Data Transformation & Visualization
 
Dimensional model xây bằng dbt + BigQuery, transform dữ liệu từ raw layer (MongoDB → GCS → BigQuery) thành star schema phục vụ báo cáo doanh thu, phân tích địa lý, xu hướng thời gian và hiệu suất sản phẩm.
 
## Kiến trúc
 
```
raw_glamira (BigQuery raw layer)
        │
        ▼
   staging  ── làm sạch 1-1, unnest JSON, chuẩn hóa định dạng
        │
        ▼
   core     ── dimensional model (6 dim + 2 fact)
        │
        ▼
   mart     ── bảng phẳng tổng hợp, phục vụ Looker Studio
```
 
## Cấu trúc thư mục
 
```
models/
├── staging/       # làm sạch raw data, unnest cart_products, parse giá/tiền tệ
├── core/          # dim_date, dim_customer, dim_product, dim_location,
│                  # dim_currency, dim_store, fact_sales_order_detail, fact_exchange_rate
└── mart/          # mart_sales_order_detail (join sẵn cho BI tool)
macros/            # parse_price - macro xử lý giá đa định dạng (EU/US)
seeds/             # seed_currency_rates - mapping ký hiệu tiền tệ → ISO + tỷ giá
scripts/           # lịch sử các script debug/rebuild trong quá trình phát triển
```
 
## Các quyết định kỹ thuật đáng chú ý
 
### 1. Dùng kiểu JSON cho field đa hình (`option`, `cart_products`)
Raw data có field `option` khi thì là mảng object, khi thì là object phẳng key-value động tùy loại sự kiện — BigQuery không cho phép 1 cột vừa ARRAY vừa OBJECT. Giải pháp: lưu nguyên dạng JSON ở raw layer, parse bằng `JSON_QUERY_ARRAY()`/`JSON_VALUE()` ở staging tùy ngữ cảnh.
 
### 2. Macro `parse_price` xử lý giá đa định dạng
Dữ liệu giá trộn lẫn định dạng châu Âu (`"2.962,00"`) và Mỹ (`"1,094.00"`) trong cùng dataset. Macro xác định dấu thập phân dựa trên vị trí xuất hiện sau cùng, có xử lý riêng trường hợp dấu ngăn nghìn (theo sau bởi đúng 3 chữ số).
 
### 3. Currency là ký hiệu, không phải mã ISO
36 ký hiệu tiền tệ khác nhau (`€`, `AU $`, `₺`...) được map thủ công sang mã ISO 4217 qua seed `seed_currency_rates.csv`.
 
### 4. Surrogate key bằng `FARM_FINGERPRINT()`
Dùng hàm băm có sẵn của BigQuery thay vì cài thêm package `dbt_utils`, giảm phụ thuộc ngoài.
 
### 5. "Unknown member" pattern cho referential integrity
Mỗi dimension có 1 dòng `key = -1` đại diện "không xác định". Fact table không bao giờ mất dòng doanh thu chỉ vì thiếu 1 dimension liên quan (ví dụ IP không tra được vị trí địa lý) — luôn `COALESCE(..., -1)` thay vì để NULL hoặc xóa dòng.
 
## Giới hạn đã biết (Known Limitations)
 
- **`fact_exchange_rate`**: tỷ giá là giá trị **tĩnh, xấp xỉ** (seed), không phải tỷ giá lịch sử theo từng ngày thật — do không có nguồn FX lịch sử trong dữ liệu MongoDB gốc. Có thể mở rộng bằng cách tích hợp API tỷ giá lịch sử (ví dụ exchangerate.host) theo `date_key`.
- **`dim_customer`** (SCD Type 2 shape): schema đã sẵn sàng cho SCD2 (`start_date`, `end_date`, `is_current`), nhưng hiện tại populate ở dạng "snapshot hiện tại" (mọi dòng `is_current = true`). Track lịch sử thay đổi thật sự cần triển khai `dbt snapshot` (thư mục `snapshots/` để trống, chuẩn bị cho việc này).
- **`location_key = -1`** (~309 dòng trong fact): do ~36,767 IP bị thiếu ở bước xử lý IP2Location tại Phần 1/2 (lỗi tra cứu bị bỏ qua âm thầm), chưa kịp khắc phục triệt để.
## Cách chạy
 
```bash
pip install dbt-bigquery
dbt debug          # kiem tra ket noi
dbt seed           # nap du lieu seed
dbt build          # chay toan bo model + test
```
 
## Data Tests
 
`_core_models.yml`, `_mart_models.yml` khai báo test `unique`, `not_null`, `relationships` cho toàn bộ dim/fact — 43/43 PASS ở lần chạy gần nhất.


### Resources:
- Learn more about dbt [in the docs](https://docs.getdbt.com/docs/introduction)
- Check out [Discourse](https://discourse.getdbt.com/) for commonly asked questions and answers
- Join the [chat](https://community.getdbt.com/) on Slack for live discussions and support
- Find [dbt events](https://events.getdbt.com) near you
- Check out [the blog](https://blog.getdbt.com/) for the latest news on dbt's development and best practices
