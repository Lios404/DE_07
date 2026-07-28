import asyncio
import json
import csv
import random
import os
import logging
from collections import Counter
from urllib.parse import urlparse
from playwright.async_api import async_playwright
from bs4 import BeautifulSoup

INPUT_CSV = "product_urls_to_crawl.csv"       # nguồn: product_id + url gốc (dùng để suy ra domain)
OUTPUT_JSONL = "products_raw.jsonl"
FAILED_CSV = "failed_products.csv"
LOG_FILE = "crawl_log.log"

CONCURRENCY = 25          # batch 20-30 theo yêu cầu của thầy
NAV_TIMEOUT = 20000
MAX_FALLBACK_DOMAINS = 4  # thử tối đa domain gốc + 4 domain dự phòng = 5 lần / sản phẩm nếu cần
SLEEP_MIN, SLEEP_MAX = 0.3, 0.8

# ------------------- LOGGING SETUP -------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler()  # vẫn in ra console song song
    ]
)
logger = logging.getLogger("glamira_crawler")

write_lock = asyncio.Lock()
progress_counter = {"done": 0, "success": 0, "failed": 0}
progress_lock = asyncio.Lock()


# ------------------- PARSING HELPERS -------------------
def extract_meta(soup, prop_name, attr="property"):
    tag = soup.find("meta", attrs={attr: prop_name})
    return tag["content"].strip() if tag and tag.get("content") else None


def extract_react_data(html):
    """
    Trích xuất biến JS `var react_data = {...};` nhúng trong HTML.
    Không dùng regex vì JSON lồng nhau rất sâu (options/stones/media) — 
    dùng thuật toán đếm ngoặc (bracket matching) để tìm đúng vị trí kết thúc object,
    có xử lý dấu ngoặc kép và ký tự escape bên trong string.
    """
    marker = "var react_data = "
    idx = html.find(marker)
    if idx == -1:
        return None

    brace_start = html.find("{", idx + len(marker))
    if brace_start == -1:
        return None

    depth = 0
    in_string = False
    escape = False
    end = None

    for i in range(brace_start, len(html)):
        c = html[i]
        if in_string:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
        else:
            if c == '"':
                in_string = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break

    if end is None:
        return None

    json_str = html[brace_start:end]
    try:
        return json.loads(json_str)
    except json.JSONDecodeError:
        return None


def parse_product(html, product_id, url, domain):
    react_data = extract_react_data(html)
    if not react_data:
        return None

    attrs = react_data.get("attributes", {}) or {}

    data = {
        "product_id": str(react_data.get("product_id", product_id)),
        "source_url": url,
        "domain_used": domain,
        "name": react_data.get("name"),
        "sku": react_data.get("sku"),
        "attribute_set": react_data.get("attribute_set"),
        "type_id": react_data.get("type_id"),
        "price": react_data.get("price"),
        "min_price": react_data.get("min_price"),
        "max_price": react_data.get("max_price"),
        "min_price_format": react_data.get("min_price_format"),
        "max_price_format": react_data.get("max_price_format"),
        "gold_weight": react_data.get("gold_weight"),
        "collection": react_data.get("collection"),
        "collection_id": react_data.get("collection_id"),
        "product_type": react_data.get("product_type"),
        "category": react_data.get("category"),
        "category_name": react_data.get("category_name"),
        "store_code": react_data.get("store_code"),
        "gender": react_data.get("gender") or (attrs.get("gender", {}) or {}).get("value"),
        "massiv": (attrs.get("massiv", {}) or {}).get("value"),
    }
    return data


def is_invalid_page(html):
    """Nhận diện trang lỗi/bị chặn/404 để biết khi nào cần đổi domain."""
    if not html or len(html) < 1000:
        return True, "empty_or_too_short"
    if "Access Denied" in html:
        return True, "access_denied"
    lowered = html.lower()
    if "404 not found" in lowered or "page not found" in lowered:
        return True, "404_not_found"
    return False, None


# ------------------- I/O HELPERS -------------------
def load_already_done():
    done_ids = set()
    if os.path.exists(OUTPUT_JSONL):
        with open(OUTPUT_JSONL, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    obj = json.loads(line)
                    done_ids.add(obj["product_id"])
                except Exception:
                    continue
    return done_ids


async def append_result(data):
    async with write_lock:
        with open(OUTPUT_JSONL, "a", encoding="utf-8") as f:
            f.write(json.dumps(data, ensure_ascii=False) + "\n")


async def append_failed(row):
    async with write_lock:
        file_exists = os.path.exists(FAILED_CSV)
        with open(FAILED_CSV, "a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["product_id", "domains_tried", "last_error"])
            if not file_exists:
                writer.writeheader()
            writer.writerow(row)


# ------------------- DOMAIN FALLBACK LOGIC -------------------
def build_domain_plan(all_rows):
    """
    Trả về:
      - product_domain_map: {product_id: domain_goc}
      - fallback_domains: list domain phổ biến nhất trong dataset (dùng làm phương án dự phòng)
    """
    domain_counter = Counter()
    product_domain_map = {}

    for pid, url in all_rows:
        domain = urlparse(url).netloc
        product_domain_map[pid] = domain
        domain_counter[domain] += 1

    fallback_domains = [d for d, _ in domain_counter.most_common(20)]
    return product_domain_map, fallback_domains


def get_attempt_domains(original_domain, fallback_domains):
    others = [d for d in fallback_domains if d != original_domain][:MAX_FALLBACK_DOMAINS]
    return [original_domain] + others


# ------------------- CRAWL CORE -------------------
async def try_one_domain(context, product_id, domain):
    """Thử crawl 1 domain cho 1 product_id. Trả về (data, error)."""
    catalog_url = f"https://{domain}/catalog/product/view/id/{product_id}"
    page = await context.new_page()
    try:
        await page.goto(catalog_url, timeout=NAV_TIMEOUT, wait_until="domcontentloaded")
        await page.wait_for_timeout(1000)  # chờ ngắn để JS phụ render kịp, tránh networkidle rủi ro
        html = await page.content()

        invalid, reason = is_invalid_page(html)
        if invalid:
            return None, reason

        data = parse_product(html, product_id, catalog_url, domain)
        if not data:
            return None, "react_data_not_found"
        if not data.get("name"):
            return None, "no_product_name_found"
        return data, None

    except Exception as e:
        return None, str(e)
    finally:
        await page.close()


async def crawl_one(context, semaphore, product_id, original_domain, fallback_domains, total):
    async with semaphore:
        attempt_domains = get_attempt_domains(original_domain, fallback_domains)
        domains_tried = []
        last_error = None
        result = None

        for domain in attempt_domains:
            domains_tried.append(domain)
            data, error = await try_one_domain(context, product_id, domain)

            if data:
                logger.info(f"SUCCESS product_id={product_id} domain={domain} attempts={len(domains_tried)}")
                result = data
                break
            else:
                last_error = error
                logger.warning(f"FAILED_ATTEMPT product_id={product_id} domain={domain} reason={error}")
                await asyncio.sleep(random.uniform(SLEEP_MIN, SLEEP_MAX))

        if result:
            await append_result(result)
            async with progress_lock:
                progress_counter["success"] += 1
        else:
            logger.error(f"ALL_DOMAINS_FAILED product_id={product_id} domains_tried={domains_tried} last_error={last_error}")
            await append_failed({
                "product_id": product_id,
                "domains_tried": ";".join(domains_tried),
                "last_error": last_error
            })
            async with progress_lock:
                progress_counter["failed"] += 1

        async with progress_lock:
            progress_counter["done"] += 1
            if progress_counter["done"] % 100 == 0:
                logger.info(
                    f"TIẾN ĐỘ: {progress_counter['done']}/{total} "
                    f"(thành công: {progress_counter['success']}, lỗi: {progress_counter['failed']})"
                )

        await asyncio.sleep(random.uniform(SLEEP_MIN, SLEEP_MAX))


# ------------------- MAIN -------------------
async def main():
    with open(INPUT_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        all_rows = [(row["product_id"], row["url"]) for row in reader]
        # Bỏ comment dòng dưới khi muốn test số lượng nhỏ trước khi chạy full
        all_rows = all_rows[:20]

    product_domain_map, fallback_domains = build_domain_plan(all_rows)

    done_ids = load_already_done()
    tasks = [pid for pid, _ in all_rows if pid not in done_ids]

    logger.info(f"Tổng số sản phẩm: {len(all_rows)}")
    logger.info(f"Đã crawl trước đó: {len(done_ids)}")
    logger.info(f"Còn lại cần crawl: {len(tasks)}")
    logger.info(f"Danh sách domain dự phòng (top phổ biến): {fallback_domains}")

    if not tasks:
        logger.info("Không còn sản phẩm nào cần crawl.")
        return

    semaphore = asyncio.Semaphore(CONCURRENCY)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
            )
        )

        coros = [
            crawl_one(context, semaphore, pid, product_domain_map[pid], fallback_domains, len(tasks))
            for pid in tasks
        ]
        await asyncio.gather(*coros)

        await browser.close()

    logger.info(f"HOÀN TẤT. Thành công: {progress_counter['success']}, Thất bại: {progress_counter['failed']}")


if __name__ == "__main__":
    asyncio.run(main())