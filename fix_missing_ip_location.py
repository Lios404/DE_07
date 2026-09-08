import os
import json
from pymongo import MongoClient
import IP2Location
from dotenv import load_dotenv

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI")
BIN_FILE_PATH = "IP-COUNTRY-REGION-CITY.BIN"
OUTPUT_JSONL = "ip_location_delta.jsonl"


def main():
    client = MongoClient(MONGO_URI)
    db = client.get_database()
    summary = db["summary"]
    ip_location = db["ip_location"]

    print("Đang lấy danh sách IP đã có trong ip_location...")
    existing_ips = set(doc["ip"] for doc in ip_location.find({}, {"ip": 1, "_id": 0}))
    print(f"Đã có: {len(existing_ips):,} IP")

    print("Đang lấy danh sách IP distinct từ summary (có thể mất chút thời gian)...")
    pipeline = [{"$group": {"_id": "$ip"}}]
    all_ips = set(
        doc["_id"] for doc in summary.aggregate(pipeline, allowDiskUse=True) if doc["_id"]
    )
    print(f"Tổng số IP distinct trong summary: {len(all_ips):,}")

    missing_ips = all_ips - existing_ips
    print(f"Số IP còn thiếu cần xử lý: {len(missing_ips):,}")

    if not missing_ips:
        print("Không có IP nào thiếu — không cần làm gì thêm.")
        return

    print("Đang load IP2Location database...")
    ip2loc = IP2Location.IP2Location(BIN_FILE_PATH)

    results = []
    errors = []
    for ip in missing_ips:
        try:
            rec = ip2loc.get_all(ip)
            results.append({
                "ip": ip,
                "country_code": rec.country_short,
                "country_name": rec.country_long,
                "region_name": rec.region,
                "city_name": rec.city,
            })
        except Exception as e:
            errors.append({"ip": ip, "error": str(e)})
            continue

    print(f"Xử lý thành công: {len(results):,}, lỗi: {len(errors):,}")

    if errors:
        with open("ip_location_delta_errors.csv", "w", encoding="utf-8") as f:
            f.write("ip,error\n")
            for e in errors:
                f.write(f"{e['ip']},{e['error']}\n")
        print(f"Danh sách IP lỗi (nếu có) đã ghi vào ip_location_delta_errors.csv")

    # Ghi vào MongoDB (đồng bộ nguồn gốc)
    if results:
        ip_location.insert_many(results)
        print(f"Đã thêm {len(results):,} document vào MongoDB collection 'ip_location'")

    # Ghi ra file JSONL để upload lên GCS -> Cloud Function tự động WRITE_APPEND vào BigQuery
    with open(OUTPUT_JSONL, "w", encoding="utf-8") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"Đã ghi file {OUTPUT_JSONL} — upload file này lên GCS để tự động cập nhật BigQuery")

    client.close()


if __name__ == "__main__":
    main()
