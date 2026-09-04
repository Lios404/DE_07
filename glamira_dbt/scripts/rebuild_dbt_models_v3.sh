#!/bin/bash
set -e

cd ~/glamira-pipeline/glamira_dbt
mkdir -p macros models/staging models/core seeds

# ============ MACRO: PARSE GIA DA DINH DANG (EU "2.962,00" va US "1,094.00") ============
cat > macros/parse_price.sql << 'EOF'
{% macro parse_price(price_col) %}
case
    when {{ price_col }} is null or trim({{ price_col }}) = '' then null

    -- Khong co dau phan cach: parse truc tiep
    when not regexp_contains({{ price_col }}, r'[.,]')
        then safe_cast({{ price_col }} as float64)

    -- Dau phan cach cuoi cung theo sau boi DUNG 3 chu so -> la dau ngan nghin (vd "1.185")
    when regexp_contains({{ price_col }}, r'[.,]\d{3}$')
        then safe_cast(regexp_replace({{ price_col }}, r'[.,]', '') as float64)

    -- Dau phay nam SAU dau cham -> phay la dau thap phan (dinh dang EU: "2.962,00")
    when instr({{ price_col }}, ',', -1) > instr({{ price_col }}, '.', -1)
        then safe_cast(replace(replace({{ price_col }}, '.', ''), ',', '.') as float64)

    -- Con lai: cham la dau thap phan (dinh dang US: "1,094.00")
    else safe_cast(replace({{ price_col }}, ',', '') as float64)
end
{% endmacro %}
EOF

# ============ STAGING: unnest cart_products + parse gia + map currency ============
cat > models/staging/stg_checkout_success_cart_items.sql << 'EOF'
with source as (
    select
        _id as source_event_id,
        safe_cast(time_stamp as int64) as time_stamp,
        timestamp_seconds(safe_cast(time_stamp as int64)) as event_timestamp,
        local_time,
        nullif(trim(ip), '') as ip,
        nullif(trim(store_id), '') as store_id,
        nullif(trim(user_id_db), '') as user_id_db,
        nullif(trim(email_address), '') as email_address,
        nullif(trim(device_id), '') as device_id,
        nullif(trim(user_agent), '') as user_agent,
        order_id,
        cart_products
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success'
      and cart_products is not null
      and time_stamp is not null
),

unnested as (
    select s.*, item
    from source s,
    unnest(json_query_array(s.cart_products)) as item
),

parsed as (
    select
        source_event_id,
        time_stamp,
        event_timestamp,
        local_time,
        ip,
        store_id,
        user_id_db,
        email_address,
        device_id,
        user_agent,
        -- order_id co dang float string ("3251020421.0") -> cast qua float truoc
        safe_cast(safe_cast(order_id as float64) as int64) as order_id,
        safe_cast(json_value(item, '$.product_id') as int64) as product_id,
        safe_cast(json_value(item, '$.amount') as int64) as amount,
        json_value(item, '$.price') as price_raw,
        nullif(json_value(item, '$.currency'), '') as currency_symbol
    from unnested
    where json_value(item, '$.product_id') is not null
),

final as (
    select
        p.* except(price_raw, currency_symbol),
        {{ parse_price('p.price_raw') }} as unit_price,
        coalesce(c.currency_code, 'UNK') as currency_code
    from parsed p
    left join {{ ref('seed_currency_rates') }} c
        on c.currency_symbol = p.currency_symbol
)

select * from final
EOF

# ============ STAGING: ip location ============
cat > models/staging/stg_ip_location.sql << 'EOF'
select distinct
    nullif(trim(ip), '') as ip_address,
    nullif(trim(country_code), '') as country_code,
    nullif(trim(country_name), '') as country_name,
    nullif(trim(region_name), '') as region_name,
    nullif(trim(city_name), '') as city_name
from {{ source('raw_glamira', 'raw_ip_location') }}
where ip is not null
EOF

# ============ CORE: DIM_DATE ============
cat > models/core/dim_date.sql << 'EOF'
with bounds as (
    select date(min(event_timestamp)) as min_date, date(max(event_timestamp)) as max_date
    from {{ ref('stg_checkout_success_cart_items') }}
),
date_spine as (
    select date_day from bounds, unnest(generate_date_array(min_date, max_date)) as date_day
)
select
    cast(format_date('%Y%m%d', date_day) as int64) as date_key,
    date_day as full_date,
    extract(dayofweek from date_day) as day_of_week,
    format_date('%A', date_day) as day_name,
    extract(day from date_day) as day_of_month,
    extract(dayofyear from date_day) as day_of_year,
    extract(week from date_day) as week_of_year,
    extract(month from date_day) as month_number,
    format_date('%B', date_day) as month_name,
    extract(quarter from date_day) as quarter_number,
    extract(year from date_day) as year_number,
    extract(dayofweek from date_day) in (1, 7) as is_weekend,
    current_timestamp() as inserted_date,
    'dbt' as inserted_by,
    current_timestamp() as updated_date,
    'dbt' as updated_by
from date_spine
EOF

# ============ CORE: DIM_CUSTOMER (SCD2-ready + PII masking) ============
cat > models/core/dim_customer.sql << 'EOF'
with checkout as (
    select * from {{ ref('stg_checkout_success_cart_items') }}
    where user_id_db is not null
),
ranked as (
    select
        user_id_db, device_id, user_agent, email_address,
        row_number() over (partition by user_id_db order by event_timestamp desc) as rn,
        min(date(event_timestamp)) over (partition by user_id_db) as first_seen_date
    from checkout
),
final as (
    select
        farm_fingerprint(user_id_db) as customer_key,
        user_agent as customer_user_agent,
        user_id_db as customer_user_id_db,
        device_id as customer_device_id,
        to_hex(sha256(lower(trim(email_address)))) as customer_email_address,
        first_seen_date as start_date,
        cast(null as date) as end_date,
        true as is_current,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from ranked where rn = 1
    union all
    select -1, null, 'UNKNOWN', null, null, null, null, true,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
select * from final
EOF

# ============ CORE: DIM_PRODUCT ============
cat > models/core/dim_product.sql << 'EOF'
with products as (
    select
        safe_cast(product_id as int64) as product_id,
        name as product_name,
        sku as product_sku,
        gender as product_gender,
        safe_cast(price as numeric) as product_base_price,
        safe_cast(min_price as numeric) as product_min_price,
        safe_cast(max_price as numeric) as product_max_price
    from {{ source('raw_glamira', 'raw_products') }}
),
final as (
    select
        farm_fingerprint(cast(product_id as string)) as product_key,
        product_id, product_name, product_sku, product_gender,
        coalesce(product_base_price, 0) as product_base_price,
        coalesce(product_min_price, 0) as product_min_price,
        coalesce(product_max_price, 0) as product_max_price,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from products where product_id is not null
    union all
    select -1, -1, 'UNKNOWN', null, null, 0, 0, 0,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
select * from final
EOF

# ============ CORE: DIM_LOCATION ============
cat > models/core/dim_location.sql << 'EOF'
select
    farm_fingerprint(ip_address) as location_key,
    city_name as location_city_name,
    region_name as location_region_name,
    country_name as location_country_name,
    country_code as location_country_code,
    current_timestamp() as inserted_date, 'dbt' as inserted_by,
    current_timestamp() as updated_date, 'dbt' as updated_by
from {{ ref('stg_ip_location') }}
union all
select -1, null, null, 'Unknown', null,
       current_timestamp(), 'dbt', current_timestamp(), 'dbt'
EOF

# ============ CORE: DIM_CURRENCY ============
cat > models/core/dim_currency.sql << 'EOF'
with distinct_codes as (
    select distinct currency_code from {{ ref('seed_currency_rates') }}
)
select
    farm_fingerprint(d.currency_code) as currency_key,
    d.currency_code,
    max(s.currency_name) as currency_name,
    current_timestamp() as inserted_date, 'dbt' as inserted_by,
    current_timestamp() as updated_date, 'dbt' as updated_by
from distinct_codes d
left join {{ ref('seed_currency_rates') }} s on s.currency_code = d.currency_code
group by d.currency_code
union all
select -1, 'UNK', 'Unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
EOF

# ============ CORE: DIM_STORE ============
cat > models/core/dim_store.sql << 'EOF'
with store_domains as (
    select store_id, net.host(current_url) as domain, count(*) as cnt
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success' and store_id is not null and current_url is not null
    group by store_id, domain
),
ranked as (
    select *, row_number() over (partition by store_id order by cnt desc) as rn
    from store_domains
)
select
    farm_fingerprint(store_id) as store_key,
    safe_cast(store_id as int64) as store_id,
    domain as store_domain,
    current_timestamp() as inserted_date, 'dbt' as inserted_by,
    current_timestamp() as updated_date, 'dbt' as updated_by
from ranked where rn = 1
union all
select -1, -1, 'unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
EOF

# ============ CORE: FACT_EXCHANGE_RATE ============
cat > models/core/fact_exchange_rate.sql << 'EOF'
with dates as (select distinct date_key from {{ ref('dim_date') }}),
curr as (select currency_key, currency_code from {{ ref('dim_currency') }} where currency_key != -1),
rates as (select distinct currency_code, rate_to_usd from {{ ref('seed_currency_rates') }})
select
    farm_fingerprint(concat(cast(d.date_key as string), '-', c.currency_code)) as exchange_rate_key,
    d.date_key,
    c.currency_key,
    cast(r.rate_to_usd as numeric) as rate_to_usd
from dates d
cross join curr c
inner join rates r on r.currency_code = c.currency_code
EOF

# ============ CORE: FACT_SALES_ORDER_DETAIL ============
cat > models/core/fact_sales_order_detail.sql << 'EOF'
with cart_items as (select * from {{ ref('stg_checkout_success_cart_items') }}),
rates as (select distinct currency_code, rate_to_usd from {{ ref('seed_currency_rates') }})
select
    farm_fingerprint(concat(ci.source_event_id, '-', cast(ci.product_id as string))) as detail_key,
    coalesce(farm_fingerprint(ci.user_id_db), -1) as customer_key,
    coalesce(farm_fingerprint(cast(ci.product_id as string)), -1) as product_key,
    coalesce(farm_fingerprint(ci.ip), -1) as location_key,
    coalesce(farm_fingerprint(ci.currency_code), -1) as currency_key,
    coalesce(farm_fingerprint(ci.store_id), -1) as store_key,
    ci.order_id,
    cast(format_timestamp('%Y%m%d', ci.event_timestamp) as int64) as date_key,
    ci.local_time,
    ci.event_timestamp as timestamp,
    ci.ip,
    coalesce(ci.amount, 0) as sales_amount,
    cast(coalesce(ci.unit_price, 0) as numeric) as sales_local_price,
    cast(round(coalesce(ci.unit_price, 0) * coalesce(r.rate_to_usd, 1), 2) as numeric) as sales_usd_price,
    current_timestamp() as inserted_date, 'dbt' as inserted_by,
    current_timestamp() as updated_date, 'dbt' as updated_by
from cart_items ci
left join rates r on r.currency_code = ci.currency_code
EOF

# ============ SOURCES ============
cat > models/staging/sources.yml << 'EOF'
version: 2
sources:
  - name: raw_glamira
    database: glamira-data-project-502506
    schema: raw_glamira
    tables:
      - name: raw_summary
      - name: raw_ip_location
      - name: raw_products
EOF

# ============ TESTS ============
cat > models/core/schema.yml << 'EOF'
version: 2
models:
  - name: dim_date
    columns:
      - name: date_key
        tests: [unique, not_null]
  - name: dim_customer
    columns:
      - name: customer_key
        tests: [unique, not_null]
  - name: dim_product
    columns:
      - name: product_key
        tests: [unique, not_null]
  - name: dim_location
    columns:
      - name: location_key
        tests: [unique, not_null]
  - name: dim_currency
    columns:
      - name: currency_key
        tests: [unique, not_null]
      - name: currency_code
        tests: [not_null]
  - name: dim_store
    columns:
      - name: store_key
        tests: [unique, not_null]
  - name: fact_exchange_rate
    columns:
      - name: exchange_rate_key
        tests: [unique, not_null]
      - name: rate_to_usd
        tests: [not_null]
  - name: fact_sales_order_detail
    columns:
      - name: detail_key
        tests: [unique, not_null]
      - name: date_key
        tests:
          - not_null
          - relationships: {to: ref('dim_date'), field: date_key}
      - name: customer_key
        tests:
          - not_null
          - relationships: {to: ref('dim_customer'), field: customer_key}
      - name: product_key
        tests: [not_null]
      - name: location_key
        tests:
          - not_null
          - relationships: {to: ref('dim_location'), field: location_key}
      - name: currency_key
        tests:
          - not_null
          - relationships: {to: ref('dim_currency'), field: currency_key}
      - name: store_key
        tests:
          - not_null
          - relationships: {to: ref('dim_store'), field: store_key}
      - name: sales_amount
        tests: [not_null]
      - name: sales_local_price
        tests: [not_null]
      - name: sales_usd_price
        tests: [not_null]
EOF

echo "=========================================="
echo "Xong. Chay tiep: dbt seed && dbt build"
echo "=========================================="
