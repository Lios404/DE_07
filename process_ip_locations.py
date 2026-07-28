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
BATCH_SIZE = 10000   # Số lượng document insert mỗi đợt để chống quá tải RAM

def process_ip_locations():
    client = MongoClient(MONGO_URI)
    db = client.get_database()
    collection = db["summary"]
    ip_location_collection = db["ip_location"]

    print("Đang chuẩn bị Database và IP2Location...")
    ip2loc = IP2Location.IP2Location(BIN_FILE_PATH)
    
    # Xóa dữ liệu cũ nếu muốn chạy mới (cân nhắc tắt dòng này trên production nếu muốn ghi nối)
    ip_location_collection.delete_many({})

    if SAMPLE_LIMIT:
        pipeline = [
            {"$group": {"_id": "$ip"}},
            {"$limit": SAMPLE_LIMIT}
        ]
    else:
        pipeline = [{"$group": {"_id": "$ip"}}]

    # Định nghĩa cấu trúc cột cố định để tránh lỗi list rỗng
    fieldnames = ["ip", "country_code", "country_name", "region_name", "city_name"]

    print("Bắt đầu xử lý IP...")
    
    # Mở file CSV để ghi từng dòng một (Streaming)
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        # Dùng Cursor thay vì nạp toàn bộ vào list
        cursor = collection.aggregate(pipeline)
        
        batch = []
        total_processed = 0
        total_success = 0

        for doc in cursor:
            ip = doc.get("_id")
            if not ip:
                continue
                
            total_processed += 1

            try:
                rec = ip2loc.get_all(ip)
                
                # Check nếu IP không hợp lệ hoặc IP nội bộ
                if not rec or rec.country_short == "-":
                    continue
                    
                data = {
                    "ip": ip,
                    "country_code": rec.country_short,
                    "country_name": rec.country_long,
                    "region_name": rec.region,
                    "city_name": rec.city
                }
                
                # 1. Ghi thẳng vào CSV
                writer.writerow(data)
                
                # 2. Gom vào batch cho MongoDB
                batch.append(data)
                total_success += 1

                # Nếu đủ BATCH_SIZE -> Ghi vào Mongo và làm rỗng list
                if len(batch) >= BATCH_SIZE:
                    ip_location_collection.insert_many(batch)
                    batch.clear() # Giải phóng RAM

            except Exception as e:
                print(f"Lỗi xử lý IP {ip}: {e}")
                continue
            
            # In tiến trình mỗi 50,000 records để dễ theo dõi trên VM
            if total_processed % 50000 == 0:
                print(f"Đang chạy... Đã quét {total_processed} IPs")

        # Ghi nốt phần dư còn lại trong batch cuối cùng
        if batch:
            ip_location_collection.insert_many(batch)

    print(f"HOÀN TẤT! Quét {total_processed} IPs. Đã ghi {total_success} bản ghi thành công.")
    client.close()

if __name__ == "__main__":
    process_ip_locations()