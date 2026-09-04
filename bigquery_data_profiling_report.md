# BigQuery Data Profiling Report — Dataset `raw_glamira`

## Bảng `raw_summary`

### Schema (table name, column name, data type)

| Column | Data Type | Nullable |
|---|---|---|
| _id | STRING | YES |
| time_stamp | INT64 | YES |
| ip | STRING | YES |
| user_agent | STRING | YES |
| resolution | STRING | YES |
| user_id_db | STRING | YES |
| device_id | STRING | YES |
| api_version | STRING | YES |
| store_id | STRING | YES |
| local_time | STRING | YES |
| show_recommendation | STRING | YES |
| current_url | STRING | YES |
| referrer_url | STRING | YES |
| email_address | STRING | YES |
| recommendation | BOOL | YES |
| utm_source | STRING | YES |
| utm_medium | STRING | YES |
| collection | STRING | YES |
| product_id | STRING | YES |
| viewing_product_id | STRING | YES |
| option | ARRAY<STRUCT<option_label STRING, option_id STRING, value_label STRING, value_id STRING>> | NO |

### Null / Distinct count (tổng 41,432,473 dòng)

| Field | Null count | Null % | Distinct count |
|---|---|---|---|
| ip | 0 | 0.00% | 3,239,628 |
| product_id | 19,189,753 | 46.32% | 19,417 |
| viewing_product_id | 39,443,421 | 95.20% | 16,981 |
| current_url | 0 | 0.00% | 16,151,626 |
| referrer_url | 0 | 0.00% | 3,578,384 |
| collection | 0 | 0.00% | 27 |
| email_address | 397 | 0.00% | 31,209 |
| time_stamp | 0 | 0.00% | 5,492,095 |
| user_id_db | 0 | 0.00% | 31,128 |
| device_id | 0 | 0.00% | 7,691,556 |

## Bảng `raw_ip_location`

### Schema (table name, column name, data type)

| Column | Data Type | Nullable |
|---|---|---|
| city_name | STRING | YES |
| country_name | STRING | YES |
| country_code | STRING | YES |
| ip | STRING | YES |
| region_name | STRING | YES |
| _id | STRING | YES |

### Null / Distinct count (tổng 3,202,861 dòng)

| Field | Null count | Null % | Distinct count |
|---|---|---|---|
| ip | 0 | 0.00% | 3,202,861 |
| country_name | 0 | 0.00% | 221 |
| city_name | 0 | 0.00% | 49,343 |

## Bảng `raw_products`

### Schema (table name, column name, data type)

| Column | Data Type | Nullable |
|---|---|---|
| product_id | STRING | YES |
| source_url | STRING | YES |
| domain_used | STRING | YES |
| name | STRING | YES |
| sku | STRING | YES |
| attribute_set | STRING | YES |
| type_id | STRING | YES |
| price | STRING | YES |
| min_price | STRING | YES |
| max_price | STRING | YES |
| min_price_format | STRING | YES |
| max_price_format | STRING | YES |
| gold_weight | STRING | YES |
| collection | STRING | YES |
| collection_id | STRING | YES |
| product_type | STRING | YES |
| category | STRING | YES |
| category_name | STRING | YES |
| store_code | STRING | YES |
| gender | STRING | YES |
| massiv | STRING | YES |

### Null / Distinct count (tổng 18,925 dòng)

| Field | Null count | Null % | Distinct count |
|---|---|---|---|
| product_id | 0 | 0.00% | 18,925 |
| name | 0 | 0.00% | 18,914 |
| sku | 0 | 0.00% | 18,925 |
| price | 1 | 0.01% | 4,768 |
| category | 0 | 0.00% | 43 |
| gender | 3,861 | 20.40% | 21 |

## Kiểm tra tính nhất quán kiểu dữ liệu

- `raw_summary.time_stamp`: số dòng không parse được thành INT64 hợp lệ: **0** ✅
- `raw_products.product_id`: đã phát hiện và sửa lỗi autodetect suy luận sai thành INT64 (ban đầu), đã load lại với schema thủ công ép kiểu STRING — khớp đúng với `raw_summary.product_id` (cũng là STRING) để đảm bảo join được chính xác ở Phần 3.


## Quan hệ logic giữa các bảng (không enforce bằng constraint vật lý)

Raw layer trong BigQuery **không áp dụng PRIMARY KEY / FOREIGN KEY / NOT NULL** — đây là chủ đích
thiết kế chuẩn của raw layer: lưu dữ liệu nguyên trạng từ nguồn, không ràng buộc, để không làm
gián đoạn quá trình load nếu dữ liệu nguồn có bất thường. Các ràng buộc/quan hệ sẽ được kiểm tra
và enforce ở tầng transform (dbt tests) tại Phần 3.

Quan hệ logic (dựa theo nghiệp vụ) giữa 3 bảng:

| Từ bảng | Field | Tới bảng | Field | Loại quan hệ |
|---|---|---|---|---|
| `raw_summary` | `product_id` (hoặc `viewing_product_id`) | `raw_products` | `product_id` | Many-to-One |
| `raw_summary` | `ip` | `raw_ip_location` | `ip` | Many-to-One |

**Lưu ý**: `raw_summary.product_id` chỉ khớp với `raw_products.product_id` cho các document thuộc
6 collection liên quan tới sản phẩm (`view_product_detail`, `select_product_option`...) — các
collection khác (`view_listing_page`, `checkout`...) sẽ có `product_id` NULL, đây là hành vi đúng,
không phải lỗi dữ liệu.
