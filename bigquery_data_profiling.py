from google.cloud import bigquery

PROJECT_ID = "glamira-data-project-502506"
DATASET_ID = "raw_glamira"
REPORT_FILE = "bigquery_data_profiling_report.md"

client = bigquery.Client(project=PROJECT_ID)

# Các field quan trọng cần profiling null/distinct cho từng bảng
TABLES_KEY_FIELDS = {
    "raw_summary": [
        "ip", "product_id", "viewing_product_id", "current_url",
        "referrer_url", "collection", "email_address", "time_stamp",
        "user_id_db", "device_id",
    ],
    "raw_ip_location": ["ip", "country_name", "city_name"],
    "raw_products": ["product_id", "name", "sku", "price", "category", "gender"],
}

RELATIONSHIPS = """
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
"""


def get_schema(table_name):
    query = f"""
        SELECT column_name, data_type, is_nullable
        FROM `{PROJECT_ID}.{DATASET_ID}.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = '{table_name}'
        ORDER BY ordinal_position
    """
    return list(client.query(query).result())


def get_row_count(table_name):
    query = f"SELECT COUNT(*) AS cnt FROM `{PROJECT_ID}.{DATASET_ID}.{table_name}`"
    return list(client.query(query).result())[0]["cnt"]


def profile_field(table_name, field):
    query = f"""
        SELECT
          COUNTIF({field} IS NULL) AS null_count,
          COUNT(DISTINCT {field}) AS distinct_count
        FROM `{PROJECT_ID}.{DATASET_ID}.{table_name}`
    """
    row = list(client.query(query).result())[0]
    return row["null_count"], row["distinct_count"]


def check_timestamp_consistency():
    """Kiểm tra riêng: time_stamp trong raw_summary phải parse được thành số nguyên hợp lệ."""
    query = f"""
        SELECT COUNTIF(SAFE_CAST(time_stamp AS INT64) IS NULL AND time_stamp IS NOT NULL) AS invalid_count
        FROM `{PROJECT_ID}.{DATASET_ID}.raw_summary`
    """
    return list(client.query(query).result())[0]["invalid_count"]


def format_schema_table(schema_rows):
    lines = ["| Column | Data Type | Nullable |", "|---|---|---|"]
    for row in schema_rows:
        lines.append(f"| {row['column_name']} | {row['data_type']} | {row['is_nullable']} |")
    return "\n".join(lines)


def format_profile_table(table_name, fields):
    total = get_row_count(table_name)
    lines = ["| Field | Null count | Null % | Distinct count |", "|---|---|---|---|"]
    for f in fields:
        null_count, distinct_count = profile_field(table_name, f)
        pct = (null_count / total * 100) if total else 0
        lines.append(f"| {f} | {null_count:,} | {pct:.2f}% | {distinct_count:,} |")
    return total, "\n".join(lines)


def main():
    report = [f"# BigQuery Data Profiling Report — Dataset `{DATASET_ID}`\n"]

    for table_name, fields in TABLES_KEY_FIELDS.items():
        report.append(f"## Bảng `{table_name}`\n")

        schema_rows = get_schema(table_name)
        report.append("### Schema (table name, column name, data type)\n")
        report.append(format_schema_table(schema_rows))
        report.append("")

        total, profile_md = format_profile_table(table_name, fields)
        report.append(f"### Null / Distinct count (tổng {total:,} dòng)\n")
        report.append(profile_md)
        report.append("")

    # Check riêng tính nhất quán kiểu dữ liệu cho time_stamp
    invalid_ts = check_timestamp_consistency()
    report.append("## Kiểm tra tính nhất quán kiểu dữ liệu\n")
    report.append(
        f"- `raw_summary.time_stamp`: số dòng không parse được thành INT64 hợp lệ: **{invalid_ts}** "
        f"{'✅' if invalid_ts == 0 else '⚠️ CẦN KIỂM TRA'}"
    )
    report.append(
        "- `raw_products.product_id`: đã phát hiện và sửa lỗi autodetect suy luận sai thành INT64 "
        "(ban đầu), đã load lại với schema thủ công ép kiểu STRING — khớp đúng với "
        "`raw_summary.product_id` (cũng là STRING) để đảm bảo join được chính xác ở Phần 3.\n"
    )

    report.append(RELATIONSHIPS)

    report_text = "\n".join(report)
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write(report_text)

    print(report_text)
    print(f"\nĐã ghi báo cáo vào {REPORT_FILE}")


if __name__ == "__main__":
    main()
