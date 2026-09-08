import os
import json
from google.cloud import bigquery
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI")
PROJECT_ID = "glamira-data-project-502506"
OUTPUT_JSONL = "ip_location_delta.jsonl"


def get_missing_ips_from_bigquery():
    """raw_ip_location tren BigQuery chua duoc cap nhat gi, nen phep so sanh nay
    van cho ra dung 36,767 IP nhu lan truoc."""
    client = bigquery.Client(project=PROJECT_ID)
    query = """
        SELECT DISTINCT s.ip
        FROM `glamira-data-project-502506.raw_glamira.raw_summary` s
        LEFT JOIN `glamira-data-project-502506.raw_glamira.raw_ip_location` l
          ON l.ip = s.ip
        WHERE l.ip IS NULL AND s.ip IS NOT NULL
    """
    return set(row["ip"] for row in client.query(query).result())


def main():
    print("Dang lay lai danh sach IP con thieu tu BigQuery...")
    missing_ips = get_missing_ips_from_bigquery()
    print(f"So IP can export: {len(missing_ips):,}")

    mongo_client = MongoClient(MONGO_URI)
    db = mongo_client.get_database()
    ip_location = db["ip_location"]

    print("Dang query lai du lieu da insert tu MongoDB...")
    cursor = ip_location.find(
        {"ip": {"$in": list(missing_ips)}},
        {"_id": 0, "ip": 1, "country_code": 1, "country_name": 1, "region_name": 1, "city_name": 1}
    )

    count = 0
    with open(OUTPUT_JSONL, "w", encoding="utf-8") as f:
        for doc in cursor:
            f.write(json.dumps(doc, ensure_ascii=False) + "\n")
            count += 1

    print(f"Da ghi {count:,} dong vao {OUTPUT_JSONL}")
    mongo_client.close()


if __name__ == "__main__":
    main()
