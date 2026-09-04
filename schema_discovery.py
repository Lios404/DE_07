import os
import json
from collections import defaultdict
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI")
SAMPLE_SIZE = 10
REPORT_FILE = "schema_discovery_report.md"


def infer_type(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def walk_document(doc, prefix=""):
    """Duyệt đệ quy 1 document, trả về {field_path: set(types quan sát được)}."""
    fields = {}
    for key, value in doc.items():
        path = f"{prefix}.{key}" if prefix else key
        t = infer_type(value)
        fields.setdefault(path, set()).add(t)

        if t == "object":
            for k, v in walk_document(value, path).items():
                fields.setdefault(k, set()).update(v)

        elif t == "array" and value:
            first = value[0]
            elem_type = infer_type(first)
            fields.setdefault(path + "[]", set()).add(elem_type)
            if elem_type == "object":
                for k, v in walk_document(first, path + "[]").items():
                    fields.setdefault(k, set()).update(v)

    return fields


def main():
    client = MongoClient(MONGO_URI)
    db = client.get_database()
    coll = db["summary"]

    collections = coll.distinct("collection")
    print(f"Tổng số collection (event type): {len(collections)}")

    per_collection_fields = {}
    master_fields = defaultdict(set)

    for col_name in collections:
        samples = list(coll.find({"collection": col_name}).limit(SAMPLE_SIZE))
        fields = {}
        for doc in samples:
            for k, v in walk_document(doc).items():
                fields.setdefault(k, set()).update(v)
                master_fields[k].update(v)
        per_collection_fields[col_name] = fields
        print(f"[{col_name}] {len(samples)} mẫu -> {len(fields)} field")

    lines = ["# Schema Discovery Report\n"]
    lines.append(f"- Tổng số collection: **{len(collections)}**")
    lines.append(f"- Tổng số field (union toàn bộ collection): **{len(master_fields)}**\n")

    lines.append("## Master field list (union tất cả collection)\n")
    lines.append("| Field path | Observed type(s) |")
    lines.append("|---|---|")
    for field in sorted(master_fields.keys()):
        types = ", ".join(sorted(master_fields[field]))
        lines.append(f"| {field} | {types} |")

    lines.append("\n## Chi tiết theo từng collection\n")
    for col_name in collections:
        fields = per_collection_fields[col_name]
        lines.append(f"### `{col_name}` ({len(fields)} field)\n")
        lines.append("| Field path | Type(s) |")
        lines.append("|---|---|")
        for field in sorted(fields.keys()):
            types = ", ".join(sorted(fields[field]))
            lines.append(f"| {field} | {types} |")
        lines.append("")

    report = "\n".join(lines)
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write(report)

    print(f"\nĐã ghi report vào {REPORT_FILE}")
    print(f"TỔNG SỐ FIELD DUY NHẤT (SAU UNION): {len(master_fields)}")

    client.close()


if __name__ == "__main__":
    main()
