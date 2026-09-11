#!/bin/bash
set -e
 
cd ~/glamira-pipeline/glamira_dbt
 
echo "=== TACH 3 DATASET (glamira_stg / glamira_core / glamira_mart) ==="
 
cat > macros/generate_schema_name.sql << 'EOF'
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
EOF
 
echo "=== STAGING: tinh key 1 LAN DUY NHAT, dat ten CTE theo convention <model>_<buoc> ==="
 
# ---------- stg_location.sql: sua 2 loi tu code mau (null-truoc-hash, thieu dau phan cach) ----------
cat > models/staging/stg_location.sql << 'EOF'
with stg_location_cleaned as (
    select
        nullif(trim(ip), '') as ip_address,
        upper(nullif(trim(country_code), '')) as country_code,
        initcap(nullif(trim(country_name), '')) as country_name,
        initcap(nullif(trim(region_name), '')) as region_name,
        initcap(nullif(trim(city_name), '')) as city_name
    from {{ source('raw_glamira', 'raw_ip_location') }}
    where ip is not null
),
 
stg_location_name as (
    select
        ip_address,
        case
            when country_code is null then null
            when regexp_contains(country_code, r'^[A-Z]{2}$') then country_code
            else null
        end as country_code,
        case
            when country_name is null or upper(country_name) like '%INVALID%'
                 or upper(country_name) like '%MISSING%' or country_name = '-'
            then null
            else country_name
        end as country_name,
        case
            when region_name is null or upper(region_name) like '%INVALID%'
                 or upper(region_name) like '%MISSING%' or region_name = '-'
            then null
            else region_name
        end as region_name,
        case
            when city_name is null or upper(city_name) like '%INVALID%'
                 or upper(city_name) like '%MISSING%' or city_name = '-'
            then null
            else city_name
        end as city_name
    from stg_location_cleaned
),
 
-- QUAN TRONG: chuan hoa NULL truoc khi hash (khong sau) - dam bao key luon xac dinh,
-- khong phu thuoc hanh vi CONCAT/|| tra ve NULL khi bat ky thanh phan nao NULL.
stg_location_normalized as (
    select
        ip_address,
        coalesce(country_code, 'UNK') as country_code,
        coalesce(country_name, 'UNK') as country_name,
        coalesce(region_name, 'UNK') as region_name,
        coalesce(city_name, 'UNK') as city_name
    from stg_location_name
),
 
stg_location_hash_key as (
    select
        -- To hop toan UNK -> gan cung -1 (dai dien Unknown chung), khac cac to hop
        -- BIET MOT PHAN (vd co country nhung thieu city) van giu key rieng vi la
        -- dia diem nghiep vu that, chi thieu 1 phan thong tin.
        case
            when country_code = 'UNK' and region_name = 'UNK' and city_name = 'UNK' then -1
            -- them dau '-' phan cach de tranh va cham khi noi chuoi
            else farm_fingerprint(country_code || '-' || region_name || '-' || city_name)
        end as location_key,
        ip_address,
        country_code,
        country_name,
        region_name,
        city_name
    from stg_location_normalized
)
 
select * from stg_location_hash_key
EOF
 
# ---------- stg_currency.sql: them currency_key, gan san -1 cho UNK ngay tai staging ----------
cat > models/staging/stg_currency.sql << 'EOF'
with stg_currency_source as (
    select cart_products
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success' and cart_products is not null
),
 
stg_currency_symbols as (
    select distinct
        nullif(json_value(item, '$.currency'), '') as currency_symbol
    from stg_currency_source s,
    unnest(json_query_array(s.cart_products)) as item
),
 
stg_currency_mapped as (
    select
        s.currency_symbol,
        coalesce(r.currency_code, 'UNK') as currency_code,
        r.currency_name
    from stg_currency_symbols s
    left join {{ ref('seed_currency_rates') }} r
        on r.currency_symbol = s.currency_symbol
),
 
stg_currency_hash_key as (
    select
        case
            when currency_code = 'UNK' then -1
            else farm_fingerprint(currency_code)
        end as currency_key,
        currency_symbol,
        currency_code,
        currency_name
    from stg_currency_mapped
)
 
select * from stg_currency_hash_key
EOF
 
# ---------- stg_store.sql: them store_key ----------
cat > models/staging/stg_store.sql << 'EOF'
with stg_store_domains as (
    select
        nullif(trim(store_id), '') as store_id,
        net.host(current_url) as domain,
        count(*) as cnt
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success'
      and store_id is not null
      and current_url is not null
    group by store_id, domain
),
 
stg_store_ranked as (
    select *,
        row_number() over (partition by store_id order by cnt desc) as rn
    from stg_store_domains
),
 
stg_store_top_domain as (
    select store_id, domain as store_domain
    from stg_store_ranked
    where rn = 1
),
 
stg_store_hash_key as (
    select
        farm_fingerprint(store_id) as store_key,
        store_id,
        store_domain
    from stg_store_top_domain
)
 
select * from stg_store_hash_key
EOF
 
# ---------- stg_products.sql: them product_key ----------
cat > models/staging/stg_products.sql << 'EOF'
with stg_products_source as (
    select
        product_id, name as product_name, sku as product_sku, gender,
        price, min_price, max_price
    from {{ source('raw_glamira', 'raw_products') }}
),
 
stg_products_cleaned as (
    select
        cast(product_id as int64) as product_id,
        nullif(trim(product_name), '') as product_name,
        nullif(trim(product_sku), '') as product_sku,
        case
            when gender is null or trim(gender) = '' then 'Unknown'
            when lower(trim(gender)) in (
                'women', 'female', 'femelle', 'femeie', 'kadın', 'mujer', 'női',
                'frauen', 'sieviete', 'vrouw', 'женски', 'donna', 'kvinne',
                'naine', 'nainen', 'žena', 'ženski'
            ) then 'Female'
            when lower(trim(gender)) = 'men' then 'Male'
            when lower(trim(gender)) in ('kids', 'çocuk') then 'Kids'
            else 'Unknown'
        end as product_gender,
        safe_cast(price as numeric) as product_base_price,
        safe_cast(min_price as numeric) as product_min_price,
        safe_cast(max_price as numeric) as product_max_price
    from stg_products_source
    where product_id is not null
),
 
stg_products_hash_key as (
    select
        farm_fingerprint(cast(product_id as string)) as product_key,
        product_id,
        product_name,
        product_sku,
        product_gender,
        product_base_price,
        product_min_price,
        product_max_price
    from stg_products_cleaned
)
 
select * from stg_products_hash_key
EOF
 
# ---------- stg_checkout_success_cart_items.sql: them customer_key tinh san ----------
cat > models/staging/stg_checkout_success_cart_items.sql << 'EOF'
with stg_checkout_success_cart_items_source as (
    select
        _id as source_event_id,
        cast(time_stamp as int64) as time_stamp,
        timestamp_seconds(cast(time_stamp as int64)) as event_timestamp,
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
 
stg_checkout_success_cart_items_unnested as (
    select s.*, item, item_index
    from stg_checkout_success_cart_items_source s,
    unnest(json_query_array(s.cart_products)) as item with offset as item_index
),
 
stg_checkout_success_cart_items_parsed as (
    select
        source_event_id,
        item_index,
        time_stamp,
        event_timestamp,
        date(event_timestamp) as order_date,
        local_time,
        ip,
        store_id,
        user_id_db,
        -- customer_key tinh 1 LAN DUY NHAT o day, dim_customer va fact chi lay lai
        farm_fingerprint(user_id_db) as customer_key,
        email_address,
        device_id,
        user_agent,
        safe_cast(safe_cast(order_id as float64) as int64) as order_id,
        safe_cast(json_value(item, '$.product_id') as int64) as product_id,
        safe_cast(json_value(item, '$.amount') as int64) as amount,
        json_value(item, '$.price') as price_raw,
        nullif(json_value(item, '$.currency'), '') as currency_symbol
    from stg_checkout_success_cart_items_unnested
    where json_value(item, '$.product_id') is not null
),
 
stg_checkout_success_cart_items_priced as (
    select
        p.* except(price_raw, currency_symbol),
        {{ parse_price('p.price_raw') }} as unit_price,
        cur.currency_code
    from stg_checkout_success_cart_items_parsed p
    left join {{ ref('stg_currency') }} cur
        on cur.currency_symbol = p.currency_symbol
),
 
stg_checkout_success_cart_items_deduplicated as (
    select *
    from stg_checkout_success_cart_items_priced
    -- Dedupe duplicate tracking event: order_id=5050209617 tung co 17 event trung
    -- trong ~6 phut, cung product/amount/price. Giu ban ghi SOM NHAT.
    qualify row_number() over (
        partition by order_id, product_id
        order by event_timestamp asc
    ) = 1
)
 
select * from stg_checkout_success_cart_items_deduplicated
EOF
 
echo "=== CORE: DIM va FACT chi LAY LAI key da tinh san tu staging ==="
 
# ---------- dim_location.sql ----------
cat > models/core/dim_location.sql << 'EOF'
with dim_location_source as (
    select * from {{ ref('stg_location') }}
),
 
dim_location_distinct as (
    select distinct
        location_key,
        country_code,
        country_name,
        region_name,
        city_name
    from dim_location_source
    where location_key != -1
),
 
dim_location_final as (
    select
        location_key,
        city_name as location_city_name,
        region_name as location_region_name,
        country_name as location_country_name,
        country_code as location_country_code,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_location_distinct
 
    union all
 
    select -1, null, null, 'Unknown', null,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_location_final
EOF
 
# ---------- dim_currency.sql ----------
cat > models/core/dim_currency.sql << 'EOF'
with dim_currency_source as (
    select * from {{ ref('stg_currency') }}
),
 
dim_currency_distinct as (
    select distinct
        currency_key,
        currency_code,
        currency_name
    from dim_currency_source
    where currency_key != -1
),
 
dim_currency_final as (
    select
        currency_key,
        currency_code,
        currency_name,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_currency_distinct
 
    union all
 
    select -1, 'UNK', 'Unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_currency_final
EOF
 
# ---------- dim_store.sql ----------
cat > models/core/dim_store.sql << 'EOF'
with dim_store_source as (
    select * from {{ ref('stg_store') }}
),
 
dim_store_final as (
    select
        store_key,
        cast(store_id as int64) as store_id,
        store_domain,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_store_source
 
    union all
 
    select -1, -1, 'unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_store_final
EOF
 
# ---------- dim_product.sql ----------
cat > models/core/dim_product.sql << 'EOF'
with dim_product_source as (
    select * from {{ ref('stg_products') }}
),
 
dim_product_final as (
    select
        product_key,
        product_id,
        product_name,
        product_sku,
        product_gender,
        coalesce(product_base_price, 0) as product_base_price,
        coalesce(product_min_price, 0) as product_min_price,
        coalesce(product_max_price, 0) as product_max_price,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_product_source
 
    union all
 
    select -1, -1, 'UNKNOWN', null, 'Unknown', 0, 0, 0,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_product_final
EOF
 
# ---------- dim_customer.sql: lay customer_key co san tu stg_checkout ----------
cat > models/core/dim_customer.sql << 'EOF'
with dim_customer_checkout as (
    select * from {{ ref('stg_checkout_success_cart_items') }}
    where user_id_db is not null
),
 
dim_customer_ranked as (
    select
        customer_key,
        user_id_db,
        device_id,
        user_agent,
        email_address,
        row_number() over (partition by customer_key order by event_timestamp desc) as rn,
        min(date(event_timestamp)) over (partition by customer_key) as first_seen_date
    from dim_customer_checkout
),
 
dim_customer_final as (
    select
        customer_key,
        user_agent as customer_user_agent,
        user_id_db as customer_user_id_db,
        device_id as customer_device_id,
        to_hex(sha256(lower(trim(email_address)))) as customer_email_address,
        first_seen_date as start_date,
        cast(null as date) as end_date,
        true as is_current,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_customer_ranked
    where rn = 1
 
    union all
 
    select -1, null, 'UNKNOWN', null, null, null, null, true,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_customer_final
EOF
 
# ---------- dim_date.sql: chi doi ten CTE cho dong bo phong cach ----------
cat > models/core/dim_date.sql << 'EOF'
with dim_date_bounds as (
    select
        date(min(event_timestamp)) as min_date,
        date(max(event_timestamp)) as max_date
    from {{ ref('stg_checkout_success_cart_items') }}
),
 
dim_date_spine as (
    select date_day
    from dim_date_bounds, unnest(generate_date_array(min_date, max_date)) as date_day
),
 
dim_date_final as (
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
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_date_spine
)
 
select * from dim_date_final
EOF
 
echo "=== FACT: chi JOIN lay key co san, khong tu tinh lai / khong can validate lai qua dim ==="
 
cat > models/core/fact_sales_order_detail.sql << 'EOF'
{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['order_id', 'product_id'],
        on_schema_change='fail'
    )
}}
 
with fact_sales_order_detail_cart_items as (
    select * from {{ ref('stg_checkout_success_cart_items') }}
    {% if is_incremental() %}
        where order_date >= date_sub(current_date(), interval 3 day)
    {% endif %}
),
 
fact_sales_order_detail_rates as (
    select distinct currency_code, rate_to_usd
    from {{ ref('seed_currency_rates') }}
),
 
fact_sales_order_detail_location as (
    select ip_address, location_key from {{ ref('stg_location') }}
),
 
fact_sales_order_detail_currency as (
    select currency_code, currency_key from {{ ref('stg_currency') }}
),
 
fact_sales_order_detail_store as (
    select store_id, store_key from {{ ref('stg_store') }}
),
 
fact_sales_order_detail_product as (
    select product_id, product_key from {{ ref('stg_products') }}
),
 
fact_sales_order_detail_final as (
    select
        farm_fingerprint(concat(
            cast(ci.order_id as string), '-',
            cast(ci.product_id as string), '-',
            cast(ci.item_index as string)
        )) as detail_key,
 
        farm_fingerprint(concat(cast(ci.order_id as string), '-', cast(ci.product_id as string))) as order_product_key,
 
        coalesce(ci.customer_key, -1) as customer_key,
        coalesce(p.product_key, -1) as product_key,
        coalesce(loc.location_key, -1) as location_key,
        coalesce(cur.currency_key, -1) as currency_key,
        coalesce(st.store_key, -1) as store_key,
 
        ci.order_id,
        cast(format_timestamp('%Y%m%d', ci.event_timestamp) as int64) as date_key,
        ci.local_time,
        ci.event_timestamp as timestamp,
        ci.ip,
        coalesce(ci.amount, 0) as sales_amount,
        cast(coalesce(ci.unit_price, 0) as numeric) as sales_local_price,
        cast(round(coalesce(ci.unit_price, 0) * coalesce(r.rate_to_usd, 1), 2) as numeric) as sales_usd_price,
        current_timestamp() as inserted_date,
        'dbt' as inserted_by,
        current_timestamp() as updated_date,
        'dbt' as updated_by
 
    from fact_sales_order_detail_cart_items ci
    left join fact_sales_order_detail_location loc on loc.ip_address = ci.ip
    left join fact_sales_order_detail_currency cur on cur.currency_code = ci.currency_code
    left join fact_sales_order_detail_store st on st.store_id = ci.store_id
    left join fact_sales_order_detail_product p on p.product_id = ci.product_id
    left join fact_sales_order_detail_rates r on r.currency_code = ci.currency_code
)
 
select * from fact_sales_order_detail_final
EOF
 
# ---------- fact_exchange_rate.sql: chi doi ten CTE ----------
cat > models/core/fact_exchange_rate.sql << 'EOF'
with fact_exchange_rate_dates as (
    select distinct date_key from {{ ref('dim_date') }}
),
 
fact_exchange_rate_currencies as (
    select currency_key, currency_code
    from {{ ref('dim_currency') }}
    where currency_key != -1
),
 
fact_exchange_rate_rates as (
    select distinct currency_code, rate_to_usd
    from {{ ref('seed_currency_rates') }}
),
 
fact_exchange_rate_final as (
    select
        farm_fingerprint(concat(cast(d.date_key as string), '-', c.currency_code)) as exchange_rate_key,
        d.date_key,
        c.currency_key,
        cast(r.rate_to_usd as numeric) as rate_to_usd
    from fact_exchange_rate_dates d
    cross join fact_exchange_rate_currencies c
    inner join fact_exchange_rate_rates r on r.currency_code = c.currency_code
)
 
select * from fact_exchange_rate_final
EOF
 
echo "=== MART: chi doi ten CTE cho dong bo phong cach ==="
 
cat > models/mart/mart_sales_order_detail.sql << 'EOF'
{{ config(materialized='table') }}
 
with mart_sales_order_detail_fact as (
    select * from {{ ref('fact_sales_order_detail') }}
),
mart_sales_order_detail_dim_date as (select * from {{ ref('dim_date') }}),
mart_sales_order_detail_dim_product as (select * from {{ ref('dim_product') }}),
mart_sales_order_detail_dim_location as (select * from {{ ref('dim_location') }}),
mart_sales_order_detail_dim_currency as (select * from {{ ref('dim_currency') }}),
mart_sales_order_detail_dim_store as (select * from {{ ref('dim_store') }}),
 
mart_sales_order_detail_final as (
    select
        f.detail_key,
        f.order_id,
        f.timestamp as order_timestamp,
        d.full_date,
        d.year_number,
        d.quarter_number,
        d.month_number,
        d.month_name,
        d.day_name,
        d.is_weekend,
        p.product_id,
        coalesce(p.product_name, 'Not In Catalog') as product_name,
        p.product_sku,
        coalesce(p.product_gender, 'Not In Catalog') as product_gender,
        l.location_city_name,
        l.location_region_name,
        l.location_country_name,
        l.location_country_code,
        s.store_domain,
        cur.currency_code,
        f.customer_key,
        f.sales_amount,
        cast(f.sales_local_price as float64) as sales_local_price,
        cast(f.sales_usd_price as float64) as sales_usd_price,
        cast(f.sales_amount * f.sales_usd_price as float64) as total_revenue_usd
    from mart_sales_order_detail_fact f
    left join mart_sales_order_detail_dim_date d on d.date_key = f.date_key
    left join mart_sales_order_detail_dim_product p on p.product_key = f.product_key
    left join mart_sales_order_detail_dim_location l on l.location_key = f.location_key
    left join mart_sales_order_detail_dim_currency cur on cur.currency_key = f.currency_key
    left join mart_sales_order_detail_dim_store s on s.store_key = f.store_key
)
 
select * from mart_sales_order_detail_final
EOF
 
echo "=========================================="
echo "DA VIET LAI XONG THEO PHONG CACH MOI."
echo "Buoc tiep theo: cap nhat dbt_project.yml (them +schema), roi dbt build --full-refresh"
echo "=========================================="
