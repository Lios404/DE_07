import logging
import functions_framework
from google.cloud import bigquery

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("trigger_bigquery_load")

PROJECT_ID = "glamira-data-project-502506"
DATASET_ID = "raw_glamira"

# Mapping: prefix thư mục trên GCS -> tên bảng BigQuery đích
PATH_TABLE_MAP = {
    "raw/summary/": "raw_summary",
    "raw/ip_location/": "raw_ip_location",
    "raw/products/": "raw_products",
}


def resolve_table(file_name):
    """Xác định bảng BigQuery đích dựa theo prefix của đường dẫn file trên GCS."""
    for prefix, table_name in PATH_TABLE_MAP.items():
        if file_name.startswith(prefix):
            return table_name
    return None


@functions_framework.cloud_event
def trigger_bigquery_load(cloud_event):
    """
    Cloud Function Gen 2 - kích hoạt khi có object mới được tạo (finalized) trong GCS bucket.
    1. Detect new file in GCS (qua cloud_event data)
    2. Xác định bảng BigQuery đích theo path
    3. Start BigQuery load job (WRITE_APPEND)
    4. Log results
    """
    data = cloud_event.data
    bucket_name = data.get("bucket")
    file_name = data.get("name")

    logger.info(f"Phát hiện file mới: gs://{bucket_name}/{file_name}")

    # Chỉ xử lý file .jsonl, bỏ qua các file khác (vd file test .pdf còn sót)
    if not file_name.endswith(".jsonl"):
        logger.info(f"Bỏ qua file không phải .jsonl: {file_name}")
        return

    table_name = resolve_table(file_name)
    if not table_name:
        logger.warning(f"Không xác định được bảng đích cho path: {file_name} — bỏ qua")
        return

    table_id = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
    uri = f"gs://{bucket_name}/{file_name}"

    try:
        client = bigquery.Client(project=PROJECT_ID)

        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            ignore_unknown_values=True,  # phòng trường hợp file mới có field lạ chưa có trong schema
        )

        load_job = client.load_table_from_uri(uri, table_id, job_config=job_config)
        load_job.result()  # đợi job hoàn tất

        destination_table = client.get_table(table_id)
        logger.info(
            f"THÀNH CÔNG: đã load {uri} vào {table_id}. "
            f"Số dòng thêm mới: {load_job.output_rows}. "
            f"Tổng số dòng hiện tại trong bảng: {destination_table.num_rows}"
        )

    except Exception as e:
        logger.error(f"LỖI khi load {uri} vào {table_id}: {e}")
        raise




