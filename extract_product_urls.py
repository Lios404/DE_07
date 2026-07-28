import os
import csv
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI")
OUTPUT_CSV = "product_urls_to_crawl.csv"

GROUP_1_COLLECTIONS = [
    "view_product_detail",
    "select_product_option",
    "select_product_option_quality",
    "add_to_cart_action",
    "product_detail_recommendation_visible",
    "product_detail_recommendation_noticed",
]

def extract_product_urls():
    client = MongoClient(MONGO_URI)
    db = client.get_database()
    collection = db["summary"]

    product_url_map = {}

    # --- Nhóm 1: product_id (fallback viewing_product_id) + current_url ---
    print("Đang trích xuất nhóm 1 (6 collections)...")
    pipeline_1 = [
        {"$match": {"collection": {"$in": GROUP_1_COLLECTIONS}}},
        {"$project": {
            "pid": {"$ifNull": ["$product_id", "$viewing_product_id"]},
            "url": "$current_url"
        }},
        {"$match": {"pid": {"$nin": [None, ""]}, "url": {"$nin": [None, ""]}}},
        {"$group": {"_id": "$pid", "url": {"$first": "$url"}}}
    ]
    count_1 = 0
    for doc in collection.aggregate(pipeline_1, allowDiskUse=True):
        product_url_map[doc["_id"]] = doc["url"]
        count_1 += 1
    print(f"Nhóm 1: {count_1} distinct product_id")

    # --- Nhóm 2: viewing_product_id + referrer_url ---
    print("Đang trích xuất nhóm 2 (product_view_all_recommend_clicked)...")
    pipeline_2 = [
        {"$match": {"collection": "product_view_all_recommend_clicked"}},
        {"$project": {
            "pid": "$viewing_product_id",
            "url": "$referrer_url"
        }},
        {"$match": {"pid": {"$nin": [None, ""]}, "url": {"$nin": [None, ""]}}},
        {"$group": {"_id": "$pid", "url": {"$first": "$url"}}}
    ]
    count_2_new = 0
    for doc in collection.aggregate(pipeline_2, allowDiskUse=True):
        if doc["_id"] not in product_url_map:  # chỉ thêm nếu chưa có (nhóm 1 ưu tiên hơn)
            product_url_map[doc["_id"]] = doc["url"]
            count_2_new += 1
    print(f"Nhóm 2: thêm mới {count_2_new} product_id chưa có ở nhóm 1")

    print(f"Tổng cộng: {len(product_url_map)} distinct product_id cần crawl")

    # --- Ghi ra CSV ---
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["product_id", "url"])
        for pid, url in product_url_map.items():
            writer.writerow([pid, url])

    print(f"Đã ghi ra {OUTPUT_CSV}")
    client.close()

if __name__ == "__main__":
    extract_product_urls()