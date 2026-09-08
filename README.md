# Glamira Data Pipeline

Tài liệu mô tả toàn bộ quá trình xây dựng data pipeline cho project Glamira — từ thu thập dữ liệu thô đến raw layer trên BigQuery.

---

## Kiến trúc tổng quan

```
[Local machine]                    [GCP VM - Ubuntu, e2-standard-4]
     |                                    |
     | gcloud compute scp                 +-- MongoDB 7.0 (auth enabled)
     v                                    |     database: countly
[GCP VM]  <---------------------------->  |       - summary        (41,432,473 docs)
     |                                    |       - ip_location    (3,202,861 docs)
     |                                    |
     +-- Python scripts (venv)            +-- Python scripts (venv)
           ├── process_ip_locations.py           ├── extract_product_urls.py
           ├── crawl_products_catalog.py (local)  ├── export_to_gcs.py
           ├── data_quality_check.py              └── bigquery_data_profiling.py
           └── ...

[GCS Bucket: raw-glamira-cita]
     ├── raw/summary/       (83 file .jsonl)
     ├── raw/ip_location/   (7 file .jsonl)
     └── raw/products/      (1 file .jsonl)
            |
            | (trigger tự động khi có file mới)
            v
     [Cloud Function Gen 2: trigger-bigquery-load]
            |
            v
[BigQuery dataset: raw_glamira]
     ├── raw_summary       (41,432,473 rows)
     ├── raw_ip_location   (3,239,628 rows)
     └── raw_products      (18,925 rows)
```

---

# PHẦN 1 — Data Collection & Storage Foundation

## 1.1. Môi trường & Công cụ

| Thành phần | Cấu hình |
|---|---|
| GCP Project | `glamira-data-project-502506` |
| Region | `asia-southeast1` (Singapore) |
| VM machine type | `e2-standard-4` (4 vCPU, 16GB RAM) |
| VM OS | Ubuntu 22.04 LTS |
| Boot disk | 60GB |
| Database | MongoDB 7.0 Community |
| GCS Bucket | `raw-glamira-cita` (Region, Standard storage class) |

## 1.2. Setup VM + MongoDB

```bash
sudo apt update && sudo apt install -y gnupg curl
curl -fsSL https://pgp.mongodb.com/server-7.0.asc | \
  sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update && sudo apt install -y mongodb-org
sudo systemctl start mongod && sudo systemctl enable mongod
```

Config `/etc/mongod.conf`:
```yaml
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
```

**Security (⭐)**: Firewall rule `allow-mongodb-myip` — chỉ mở TCP 27017 cho IP cá nhân (`/32`), không mở `0.0.0.0/0`. IP cá nhân là dynamic nên cần cập nhật rule định kỳ khi kết nối bị timeout.

## 1.3. Data Loading

Dataset nguồn: MongoDB dump nén `.tar.gz` (~5.2GB → ~32GB sau giải nén), chuyển thẳng local → VM bằng `gcloud compute scp` (không qua GCS trung gian vì `.bson` không phải định dạng Big Data engine đọc trực tiếp được).

```bash
mongorestore --uri="mongodb://glamira_admin:<pwd>@localhost:27017" \
  --nsInclude="countly.summary" \
  --numInsertionWorkersPerCollection=4 \
  ~/dump
```

**Kết quả**: 41,432,473 documents, 0 failures.

## 1.4. Data Dictionary — `countly.summary`

| Field | Type | Mô tả |
|---|---|---|
| `time_stamp` | Int (Unix epoch) | Thời điểm sự kiện |
| `ip` | String | IP người dùng |
| `user_id_db`, `device_id` | String | Định danh người dùng/thiết bị |
| `collection` | String | Loại sự kiện (27 giá trị) |
| `current_url`, `referrer_url` | String | Input crawl product info |
| `product_id`, `viewing_product_id` | String | Khóa sản phẩm |
| `email_address` | String | ⚠️ PII — cần masking ở Phần 3 |
| `option` | Array | Tùy chọn sản phẩm |

Top 5 `collection`: `view_listing_page` (11.2M), `view_product_detail` (10.9M), `select_product_option` (8.8M), `select_product_option_quality` (2.2M), `view_static_page` (1.45M).

## 1.5. IP Location Processing

- Thư viện `IP2Location` + file `.BIN` local (không gọi API ngoài)
- Input: 3,239,628 distinct IP từ `summary`
- Output: CSV + MongoDB collection `ip_location` (3,202,861 document sau khi enrich)
- Giới hạn: bản `.BIN` không có latitude/longitude — đã bỏ 2 field này khỏi output

## 1.6. Product Information Collection

**Trích xuất product_id + URL** (MongoDB aggregation `$group` + `$first`, đảm bảo mỗi `product_id` chỉ giữ 1 bản ghi): **19,417 distinct product_id**.

**Crawl thông tin sản phẩm**:
- Site dùng **Akamai Bot Manager** → bắt buộc dùng **Playwright** (headless browser thật), `requests`/`cloudscraper` đều bị chặn 403
- Dùng **catalog link** (`https://<domain>/catalog/product/view/id/<product_id>`) thay vì URL gốc từ MongoDB — tránh lỗi 404 do slug SEO lỗi thời/query param rác
- **Domain fallback**: nếu domain gốc không có data hợp lệ, tự động thử domain phổ biến khác trong dataset (tối đa 5 domain/sản phẩm)
- Trích xuất qua biến `react_data` nhúng trong HTML (dùng thuật toán đếm ngoặc để parse JSON lồng sâu) — nguồn dữ liệu đầy đủ hơn nhiều so với meta tags/JSON-LD
- Async + concurrency 25, logging đầy đủ (`crawl_log.log`), cơ chế resume khi bị gián đoạn
- **Chạy ở máy LOCAL** (không phải VM) — vì Akamai chặn dải IP datacenter GCP, IP nhà mạng dân dụng không bị chặn
- **Kết quả cuối**: 18,925 sản phẩm crawl thành công (0 trùng lặp `product_id`)

## 1.7. Data Quality Verification (Phần 1)

Script `data_quality_check.py` kiểm tra trên MongoDB + file local:

| Nguồn | Null/Distinct đáng chú ý |
|---|---|
| `summary` | `product_id` null 46.32% (bình thường — nhiều event type không gắn sản phẩm) |
| `ip_location` | 0 IP trùng lặp, 0 null country/city |
| `products_raw.jsonl` | 0 `product_id` trùng lặp ✅ (đúng yêu cầu "duy nhất") |

---

# PHẦN 2 — Data Pipeline & Storage

## 2.1. Data Export Process (MongoDB → GCS)

Script `export_to_gcs.py` — chạy **trên VM** (không phải local) vì chỉ đọc Mongo + ghi GCS, không gọi site ngoài nên không gặp vấn đề Akamai; tránh phải tải 32GB qua mạng cá nhân.

**Thiết kế xử lý theo batch** (không load hết vào RAM với 41M document):
- Đọc cursor MongoDB theo batch 500,000 document
- Ghi ra file JSONL tạm, upload lên GCS ngay khi đủ batch, xóa file tạm local
- Logging đầy đủ (`export_to_gcs.log`), xử lý lỗi try/except

**Kết quả**:
| Nguồn | Số file | Số dòng |
|---|---|---|
| `raw/summary/` | 83 | 41,432,473 |
| `raw/ip_location/` | 7 | 3,202,861 |
| `raw/products/` | 1 | 18,925 |

## 2.2. BigQuery Integration

### Dataset
```bash
bq mk --dataset --location=asia-southeast1 glamira-data-project-502506:raw_glamira
```

### Schema — định nghĩa thủ công cho `raw_summary` và `raw_products`

Lý do không dùng `--autodetect` cho 2 bảng này:
- `raw_summary` có field `option` dạng nested array — autodetect dễ suy luận sai
- `raw_products` từng bị autodetect suy luận sai `product_id` thành **INT64** (do giá trị trông giống số) — gây lỗi không join được với `raw_summary.product_id` (STRING). Đã phát hiện qua data profiling và sửa lại bằng schema thủ công ép `STRING`.

`raw_ip_location` dùng `--autodetect` (cấu trúc đơn giản, ít rủi ro).

```bash
bq load --source_format=NEWLINE_DELIMITED_JSON --ignore_unknown_values \
  glamira-data-project-502506:raw_glamira.raw_summary \
  "gs://raw-glamira-cita/raw/summary/*.jsonl" schema_summary.json

bq load --source_format=NEWLINE_DELIMITED_JSON --autodetect \
  glamira-data-project-502506:raw_glamira.raw_ip_location \
  "gs://raw-glamira-cita/raw/ip_location/*.jsonl"

bq load --replace --source_format=NEWLINE_DELIMITED_JSON --ignore_unknown_values \
  glamira-data-project-502506:raw_glamira.raw_products \
  "gs://raw-glamira-cita/raw/products/*.jsonl" schema_products.json
```

> **Lưu ý quan trọng**: `bq load` (CLI) mặc định `WRITE_APPEND` — chạy lệnh 2 lần sẽ nhân đôi dữ liệu mà không báo lỗi (khác với Python client, mặc định `WRITE_EMPTY`). Luôn dùng `--replace` khi load lại để đảm bảo idempotent.

### Cloud Function trigger tự động (Gen 2)

`cloud_function/main.py` — lắng nghe sự kiện `google.cloud.storage.object.v1.finalized` trên bucket, tự động xác định bảng đích theo path prefix, chạy BigQuery load job với `WRITE_APPEND`.

```bash
gcloud functions deploy trigger-bigquery-load \
  --gen2 --runtime=python312 --region=asia-southeast1 \
  --source=. --entry-point=trigger_bigquery_load \
  --trigger-bucket=raw-glamira-cita --trigger-location=asia-southeast1 \
  --memory=512MB --timeout=540s
```

**Test end-to-end**: upload file `.jsonl` mới vào bucket → Cloud Function tự động kích hoạt → BigQuery load job chạy → xác nhận qua `COUNT(*)` tăng đúng số dòng. **Kết quả: PASS** (test nhiều lần, số liệu khớp chính xác).

### Các vấn đề IAM/quyền gặp phải trong quá trình setup (đáng chú ý)

| Vấn đề | Nguyên nhân | Cách giải quyết |
|---|---|---|
| `403 Insufficient Permission` khi `bq mk` | Service Account VM thiếu role BigQuery Admin | Cấp role qua Console IAM |
| `Insufficient authentication scopes` | **VM Access Scope** giới hạn (khác IAM) — cấu hình cứng lúc tạo VM | Stop VM → đổi Access Scope thành "Allow full access to all Cloud APIs" → Start lại |
| `storage.buckets.get denied` khi deploy Cloud Function | Eventarc/Pub-Sub Service Agent chưa được khởi tạo | `gcloud beta services identity create` + cấp role `eventarc.serviceAgent`, `pubsub.publisher` |
| `Service account key creation is disabled` | Org Policy chặn tạo SA key (bảo mật doanh nghiệp) | Chuyển sang `gcloud auth application-default login` (browser-based, không tạo key file) |
| Nhiều lỗi "Permission denied" khi enable API/gán IAM từ VM | Service Account VM không có quyền `Service Usage Admin` | Chạy các lệnh `gcloud services enable` / `add-iam-policy-binding` từ **máy local** (tài khoản Owner), không phải từ VM |

## 2.3. Testing & Monitoring — Data Profiling

Script `bigquery_data_profiling.py` — kiểm tra trên BigQuery raw layer:

1. **Schema**: liệt kê column name + data type qua `INFORMATION_SCHEMA.COLUMNS`
2. **Null/Distinct count**: cho các field quan trọng của cả 3 bảng
3. **Type consistency check**: xác nhận `time_stamp` parse INT64 hợp lệ 100%; ghi nhận và khắc phục vụ `product_id` bị autodetect sai kiểu
4. **Relationships**: mô tả quan hệ logic giữa các bảng (raw layer không enforce PK/FK — đúng chuẩn thiết kế, để dbt tests xử lý ở Phần 3)

**Kết quả cuối** (sau khi sửa lỗi trùng lặp do chạy `bq load` 2 lần):

| Bảng | Số dòng | product_id type |
|---|---|---|
| `raw_summary` | 41,432,473 | STRING |
| `raw_ip_location` | 3,239,628 | — |
| `raw_products` | 18,925 | STRING (đã sửa từ INT64) |

---

## Cấu trúc thư mục project

```
glamira-pipeline/
├── .env                              # connection string, GCS bucket (không commit)
├── .gitignore
├── process_ip_locations.py           # Phần 1 - Bước 5
├── extract_product_urls.py           # Phần 1 - Bước 6a
├── crawl_products_catalog.py         # Phần 1 - Bước 6b (chạy ở local)
├── data_quality_check.py             # Phần 1 - Bước 7
├── export_to_gcs.py                  # Phần 2 - Bước 1 (chạy ở VM)
├── schema_summary.json               # Phần 2 - Bước 2
├── schema_products.json              # Phần 2 - Bước 2
├── bigquery_data_profiling.py        # Phần 2 - Bước 3
├── cloud_function/
│   ├── main.py                       # Cloud Function Gen 2
│   └── requirements.txt
├── products_raw.jsonl                # output crawl (không commit)
├── failed_products.csv
├── crawl_log.log
└── IP-COUNTRY-REGION-CITY.BIN        # không commit (dung lượng lớn)
```

## Quy trình phát triển

```
LOCAL dev (test với data mẫu nhỏ)
   → test code chạy đúng
   → PUSH GITHUB
   → SSH lên VM, git pull / clone
   → chạy full trên VM (hoặc local nếu cần, tùy đặc thù script)
```

## Deliverables

**Phần 1**: ✅ Working VM with MongoDB · ✅ Python scripts cho IP processing · ✅ Documentation cấu trúc dữ liệu · ✅ Github repository

**Phần 2**: ✅ Automated data pipeline · ✅ Cloud Function triggers · ✅ BigQuery tables · ✅ Github repository
