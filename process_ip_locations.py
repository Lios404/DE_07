import os
import csv
from pymongo import MongoClient
import IP2Location
from dotenv import load_dotenv

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI")
BIN_FILE_PATH = "IP-COUNTRY-REGION-CITY.BIN"
OUTPUT_CSV = "ip_locations.csv"
SAMPLE_LIMIT = None  # dùng để test local trước, sau chuyển None khi chạy full trên VM

def process_ip_locations():
    # 1. Connect to MongoDB
    client = MongoClient(MONGO_URI)
    db = client.get_database()
    collection = db["summary"]

    # 2. Read unique IPs from main collection
    print("Đang lấy danh sách IP duy nhất...")
    if SAMPLE_LIMIT:
        pipeline = [
            {"$group": {"_id": "$ip"}},
            {"$limit": SAMPLE_LIMIT}
        ]
    else:
        pipeline = [{"$group": {"_id": "$ip"}}]

    unique_ips = [doc["_id"] for doc in collection.aggregate(pipeline) if doc["_id"]]
    print(f"Tổng số IP duy nhất cần xử lý: {len(unique_ips)}")

    # 3. Use ip2location to get location data
    print("Đang load IP2Location database...")
    ip2loc = IP2Location.IP2Location(BIN_FILE_PATH)

    results = []
    for ip in unique_ips:
        try:
            rec = ip2loc.get_all(ip)
            results.append({
                "ip": ip,
                "country_code": rec.country_short,
                "country_name": rec.country_long,
                "region_name": rec.region,
                "city_name": rec.city
            })
        except Exception as e:
            print(f"Lỗi xử lý IP {ip}: {e}")
            continue

    print(f"Đã xử lý xong {len(results)} IP.")

    # 4. Store results in new collection AND CSV file
    # 4a. Ghi ra CSV
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=results[0].keys())
        writer.writeheader()
        writer.writerows(results)
    print(f"Đã ghi kết quả ra file {OUTPUT_CSV}")

    # 4b. Ghi vào MongoDB collection mới
    ip_location_collection = db["ip_location"]
    ip_location_collection.delete_many({})  # xóa cũ nếu chạy lại (tránh trùng lặp khi test nhiều lần)
    if results:
        ip_location_collection.insert_many(results)
    print(f"Đã ghi {len(results)} document vào MongoDB collection 'ip_location'")

    client.close()

if __name__ == "__main__":
    process_ip_locations()