#!/bin/bash
set -e

cd ~/glamira-pipeline/glamira_dbt

echo "=== Cap nhat models/core/_core_models.yml (contract + dbt_expectations toan bo core layer) ==="

cat > models/core/_core_models.yml << 'EOF'
version: 2

models:
  # ============================================================
  # DIM_DATE
  # ============================================================
  - name: dim_date
    description: "Date dimension, date spine generated tu min/max event_timestamp cua checkout data."
    config:
      contract:
        enforced: true
    columns:
      - name: date_key
        data_type: INT64
        tests: [unique, not_null]
      - name: full_date
        data_type: DATE
        tests: [not_null]
      - name: day_of_week
        data_type: INT64
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 1
              max_value: 7
      - name: day_name
        data_type: STRING
      - name: day_of_month
        data_type: INT64
      - name: day_of_year
        data_type: INT64
      - name: week_of_year
        data_type: INT64
      - name: month_number
        data_type: INT64
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 1
              max_value: 12
      - name: month_name
        data_type: STRING
      - name: quarter_number
        data_type: INT64
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 1
              max_value: 4
      - name: year_number
        data_type: INT64
      - name: is_weekend
        data_type: BOOL
      - name: inserted_date
        data_type: TIMESTAMP
      - name: inserted_by
        data_type: STRING
      - name: updated_date
        data_type: TIMESTAMP
      - name: updated_by
        data_type: STRING

  # ============================================================
  # DIM_CUSTOMER
  # ============================================================
  - name: dim_customer
    description: "Customer dimension (SCD2-ready shape). PII: email da duoc hash SHA256, khong luu plaintext."
    config:
      contract:
        enforced: true
    columns:
      - name: customer_key
        data_type: INT64
        tests: [unique, not_null]
      - name: customer_user_agent
        data_type: STRING
      - name: customer_user_id_db
        data_type: STRING
        tests: [not_null]
      - name: customer_device_id
        data_type: STRING
      - name: customer_email_address
        data_type: STRING
        description: "SHA256 hash cua email goc - kiem tra dinh dang de xac nhan PII masking hoat dong dung."
        tests:
          - dbt_expectations.expect_column_values_to_match_regex:
              regex: "^[a-f0-9]{64}$"
              row_condition: "customer_key != -1"
      - name: start_date
        data_type: DATE
      - name: end_date
        data_type: DATE
      - name: is_current
        data_type: BOOL
      - name: inserted_date
        data_type: TIMESTAMP
      - name: inserted_by
        data_type: STRING
      - name: updated_date
        data_type: TIMESTAMP
      - name: updated_by
        data_type: STRING

  # ============================================================
  # DIM_PRODUCT
  # ============================================================
  - name: dim_product
    description: "Dimension model containing standardized product information."
    config:
      contract:
        enforced: true
    columns:
      - name: product_key
        data_type: INT64
        description: "Surrogate key generated using the hash of the product identifier."
        tests:
          - unique
          - not_null
      - name: product_id
        data_type: INT64
        description: "Business identifier of the product (from raw_products)."
      - name: product_name
        data_type: STRING
        description: "Standardized product name."
      - name: product_sku
        data_type: STRING
        description: "Stock keeping unit code of the product."
      - name: product_gender
        data_type: STRING
        description: "Gender category, normalized from 22 raw distinct multi-language values into 4 categories."
        tests:
          - dbt_expectations.expect_column_values_to_be_in_set:
              value_set: ["Female", "Male", "Kids", "Unknown"]
      - name: product_base_price
        data_type: NUMERIC
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
      - name: product_min_price
        data_type: NUMERIC
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
      - name: product_max_price
        data_type: NUMERIC
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
      - name: inserted_date
        data_type: TIMESTAMP
      - name: inserted_by
        data_type: STRING
      - name: updated_date
        data_type: TIMESTAMP
      - name: updated_by
        data_type: STRING

  # ============================================================
  # DIM_LOCATION
  # ============================================================
  - name: dim_location
    description: "Geographic location dimension. Grain: 1 row per unique (country, region, city) business location, KHONG phai 1 row per IP."
    config:
      contract:
        enforced: true
    columns:
      - name: location_key
        data_type: INT64
        description: "Surrogate key generated using the hash of normalized country+region+city."
        tests:
          - unique
          - not_null
      - name: location_city_name
        data_type: STRING
      - name: location_region_name
        data_type: STRING
      - name: location_country_name
        data_type: STRING
      - name: location_country_code
        data_type: STRING
        tests:
          - dbt_expectations.expect_column_value_lengths_to_equal:
              value: 2
              row_condition: "location_key != -1"
      - name: inserted_date
        data_type: TIMESTAMP
      - name: inserted_by
        data_type: STRING
      - name: updated_date
        data_type: TIMESTAMP
      - name: updated_by
        data_type: STRING
    tests:
      - dbt_expectations.expect_compound_columns_to_be_unique:
          column_list: ["location_country_name", "location_region_name", "location_city_name"]

  # ============================================================
  # DIM_CURRENCY
  # ============================================================
  - name: dim_currency
    description: "Currency dimension, mapped tu ky hieu tien te thuc te sang ma ISO 4217."
    config:
      contract:
        enforced: true
    columns:
      - name: currency_key
        data_type: INT64
        tests: [unique, not_null]
      - name: currency_code
        data_type: STRING
        tests:
          - not_null
          - dbt_expectations.expect_column_value_lengths_to_equal:
              value: 3
      - name: currency_name
        data_type: STRING
      - name: inserted_date
        data_type: TIMESTAMP
      - name: inserted_by
        data_type: STRING
      - name: updated_date
        data_type: TIMESTAMP
      - name: updated_by
        data_type: STRING

  # ============================================================
  # DIM_STORE
  # ============================================================
  - name: dim_store
    description: "Store dimension, domain suy luan tu current_url pho bien nhat theo store_id."
    config:
      contract:
        enforced: true
    columns:
      - name: store_key
        data_type: INT64
        tests: [unique, not_null]
      - name: store_id
        data_type: INT64
        tests: [not_null]
      - name: store_domain
        data_type: STRING
        tests: [not_null]
      - name: inserted_date
        data_type: TIMESTAMP
      - name: inserted_by
        data_type: STRING
      - name: updated_date
        data_type: TIMESTAMP
      - name: updated_by
        data_type: STRING

  # ============================================================
  # FACT_EXCHANGE_RATE
  # ============================================================
  - name: fact_exchange_rate
    description: "Bang ty gia quy doi USD theo ngay x tien te. Ty gia hien la gia tri tinh/xap xi (seed), khong phai lich su thuc."
    config:
      contract:
        enforced: true
    columns:
      - name: exchange_rate_key
        data_type: INT64
        tests: [unique, not_null]
      - name: date_key
        data_type: INT64
        tests:
          - not_null
          - relationships: {to: ref('dim_date'), field: date_key}
      - name: currency_key
        data_type: INT64
        tests:
          - not_null
          - relationships: {to: ref('dim_currency'), field: currency_key}
      - name: rate_to_usd
        data_type: NUMERIC
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
              inclusive_min: false

  # ============================================================
  # FACT_SALES_ORDER_DETAIL
  # ============================================================
  - name: fact_sales_order_detail
    description: >
      Grain: 1 dong = 1 cap (order_id, product_id) DUY NHAT sau dedupe (loai bo duplicate
      tracking event - vi du order_id=5050209617 tung co 17 event trung trong ~6 phut).
      Business key: order_id + product_id + item_index (KHONG dung Mongo _id).
      Materialized incremental (merge, unique_key = order_id+product_id).
    config:
      contract:
        enforced: true
    columns:
      - name: detail_key
        data_type: INT64
        tests: [unique, not_null]
      - name: order_product_key
        data_type: INT64
        description: "Key phu ho tro dedupe/join logic theo cap order+product."
      - name: customer_key
        data_type: INT64
        tests:
          - not_null
          - relationships: {to: ref('dim_customer'), field: customer_key}
      - name: product_key
        data_type: INT64
        tests: [not_null]
      - name: location_key
        data_type: INT64
        tests:
          - not_null
          - relationships: {to: ref('dim_location'), field: location_key}
      - name: currency_key
        data_type: INT64
        tests:
          - not_null
          - relationships: {to: ref('dim_currency'), field: currency_key}
      - name: store_key
        data_type: INT64
        tests:
          - not_null
          - relationships: {to: ref('dim_store'), field: store_key}
      - name: order_id
        data_type: INT64
      - name: date_key
        data_type: INT64
        tests:
          - not_null
          - relationships: {to: ref('dim_date'), field: date_key}
      - name: local_time
        data_type: STRING
      - name: timestamp
        data_type: TIMESTAMP
      - name: ip
        data_type: STRING
      - name: sales_amount
        data_type: INT64
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
      - name: sales_local_price
        data_type: NUMERIC
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
      - name: sales_usd_price
        data_type: NUMERIC
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
      - name: inserted_date
        data_type: TIMESTAMP
      - name: inserted_by
        data_type: STRING
      - name: updated_date
        data_type: TIMESTAMP
      - name: updated_by
        data_type: STRING
    tests:
      # Row-count sanity floor - bat loi nghiem trong (vi du filter sai lam mat phan lon du lieu)
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 30000
          max_value: 50000
EOF

echo "=== Tao models/mart/_mart_models.yml (contract cho lop BI-facing) ==="

cat > models/mart/_mart_models.yml << 'EOF'
version: 2

models:
  - name: mart_sales_order_detail
    description: "Bang phang join san fact + toan bo dimension, phuc vu truc tiep Looker Studio."
    config:
      contract:
        enforced: true
    columns:
      - name: detail_key
        data_type: INT64
        tests: [unique, not_null]
      - name: order_id
        data_type: INT64
      - name: order_timestamp
        data_type: TIMESTAMP
      - name: full_date
        data_type: DATE
      - name: year_number
        data_type: INT64
      - name: quarter_number
        data_type: INT64
      - name: month_number
        data_type: INT64
      - name: month_name
        data_type: STRING
      - name: day_name
        data_type: STRING
      - name: is_weekend
        data_type: BOOL
      - name: product_id
        data_type: INT64
      - name: product_name
        data_type: STRING
      - name: product_sku
        data_type: STRING
      - name: product_gender
        data_type: STRING
      - name: location_city_name
        data_type: STRING
      - name: location_region_name
        data_type: STRING
      - name: location_country_name
        data_type: STRING
      - name: location_country_code
        data_type: STRING
      - name: store_domain
        data_type: STRING
      - name: currency_code
        data_type: STRING
      - name: customer_key
        data_type: INT64
      - name: sales_amount
        data_type: INT64
      - name: sales_local_price
        data_type: FLOAT64
      - name: sales_usd_price
        data_type: FLOAT64
      - name: total_revenue_usd
        data_type: FLOAT64
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
EOF

echo "=== Them seed test cho seed_currency_rates ==="

cat > seeds/_seeds.yml << 'EOF'
version: 2

seeds:
  - name: seed_currency_rates
    description: "Bang tinh (khong phai lich su) mapping ky hieu tien te sang ma ISO + ty gia quy doi USD."
    columns:
      - name: currency_symbol
        tests: [not_null, unique]
      - name: currency_code
        tests: [not_null]
      - name: rate_to_usd
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
              inclusive_min: false
EOF

echo "=== Them singular test: mart phai khop so dong voi fact (khong duoc lech do join sai) ==="

mkdir -p tests
cat > tests/assert_mart_matches_fact_row_count.sql << 'EOF'
-- Test PASS neu KHONG tra ve dong nao.
-- Xac nhan mart_sales_order_detail khong bi nhan doi/mat dong so voi fact
-- (co the xay ra neu 1 dimension nao do vo tinh co key trung lap).
with counts as (
    select
        (select count(*) from {{ ref('fact_sales_order_detail') }}) as fact_count,
        (select count(*) from {{ ref('mart_sales_order_detail') }}) as mart_count
)
select *
from counts
where fact_count != mart_count
EOF

echo "=========================================="
echo "DA CAP NHAT XONG. Buoc tiep theo:"
echo "1. dbt deps  (neu chua chay)"
echo "2. dbt build --full-refresh"
echo "=========================================="
