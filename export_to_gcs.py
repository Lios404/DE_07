import os
import json
import logging
import datetime
from pymongo import MongoClient
from google.cloud import storage
from bson import ObjectId
from dotenv import load_dotenv

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI")
GCS_BUCKET = os.getenv("GCS_BUCKET")  # vd: raw-glamira-<ten>
BATCH_SIZE = 500_000                  # số document mỗi part file
TEST_LIMIT = None                     # đặt số nhỏ (vd 5000) để test trước khi chạy full

# Mapping: tên collection Mongo -> prefix thư mục trên GCS
EXPORT_MAP = {
    "summary": "raw/summary/",
    "ip_location": "raw/ip_location/",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("export_to_gcs.log", encoding="utf-8"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger("export_to_gcs")


def json_default(obj):
    """Xử lý serialize các kiểu dữ liệu MongoDB đặc thù (ObjectId, datetime)."""
    if isinstance(obj, ObjectId):
        return str(obj)
    if isinstance(obj, datetime.datetime):
        return obj.isoformat()
    raise TypeError(f"Không serialize được kiểu: {type(obj)}")


def upload_part(bucket, local_path, gcs_prefix):
    """Upload 1 part file lên GCS rồi xóa file tạm ở local để tiết kiệm dung lượng đĩa."""
    filename = os.path.basename(local_path)
    blob = bucket.blob(f"{gcs_prefix}{filename}")
    blob.upload_from_filename(local_path)
    os.remove(local_path)


def export_collection_to_gcs(db, storage_client, collection_name, gcs_prefix, limit=None):
    coll = db[collection_name]
    total = coll.count_documents({})
    if limit:
        total = min(total, limit)

    logger.info(f"Bắt đầu export `{collection_name}` — tổng {total:,} documents cần xử lý")

    bucket = storage_client.bucket(GCS_BUCKET)
    cursor = coll.find({}, batch_size=2000)
    if limit:
        cursor = cursor.limit(limit)

    part_num = 0
    doc_in_part = 0
    exported_total = 0
    f = None
    local_path = None

    try:
        for doc in cursor:
            if f is None:
                part_num += 1
                local_path = f"/tmp/{collection_name}_part_{part_num:05d}.jsonl"
                f = open(local_path, "w", encoding="utf-8")
                doc_in_part = 0

            f.write(json.dumps(doc, default=json_default, ensure_ascii=False) + "\n")
            doc_in_part += 1
            exported_total += 1

            if doc_in_part >= BATCH_SIZE:
                f.close()
                upload_part(bucket, local_path, gcs_prefix)
                logger.info(
                    f"[{collection_name}] Đã upload part {part_num} "
                    f"({doc_in_part:,} docs) — tiến độ {exported_total:,}/{total:,}"
                )
                f = None

        # Flush phần dư cuối cùng (chưa đủ BATCH_SIZE)
        if f is not None:
            f.close()
            upload_part(bucket, local_path, gcs_prefix)
            logger.info(
                f"[{collection_name}] Đã upload part cuối {part_num} ({doc_in_part:,} docs)"
            )

        logger.info(
            f"HOÀN TẤT export `{collection_name}`: {exported_total:,}/{total:,} documents, "
            f"{part_num} part file(s) đã upload lên gs://{GCS_BUCKET}/{gcs_prefix}"
        )

    except Exception as e:
        logger.error(f"LỖI khi export `{collection_name}`: {e}")
        if f:
            f.close()
        raise


def main():
    if not GCS_BUCKET:
        logger.error("Chưa cấu hình GCS_BUCKET trong file .env")
        return

    client = MongoClient(MONGO_URI)
    db = client.get_database()
    storage_client = storage.Client()

    for collection_name, gcs_prefix in EXPORT_MAP.items():
        export_collection_to_gcs(db, storage_client, collection_name, gcs_prefix, limit=TEST_LIMIT)

    client.close()
    logger.info("Toàn bộ quá trình export hoàn tất.")


if __name__ == "__main__":
    main()
