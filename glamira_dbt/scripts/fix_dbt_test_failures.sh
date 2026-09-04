#!/bin/bash
set -e

cd ~/glamira-pipeline/glamira_dbt

# ============ FIX 1: STAGING - them item_index de detail_key duy nhat ============
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

-- FIX: them item_index (vi tri san pham trong gio hang) de dam bao
-- detail_key duy nhat khi 1 don mua cung 1 product_id nhieu lan (khac option)
unnested as (
    select s.*, item, item_index
    from source s,
    unnest(json_query_array(s.cart_products)) as item with offset as item_index
),

parsed as (
    select
        source_event_id,
        item_index,
        time_stamp,
        event_timestamp,
        local_time,
        ip,
        store_id,
        user_id_db,
        email_address,
        device_id,
        user_agent,
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
        -- FIX: currency khong map duoc -> NULL de fact gan ve key -1 (Unknown member)
        c.currency_code
    from parsed p
    left join {{ ref('seed_currency_rates') }} c
        on c.currency_symbol = p.currency_symbol
)

select * from final
EOF

# ============ FIX 2 + 3: FACT - surrogate key co item_index, xu ly key khong tim thay ============
cat > models/core/fact_sales_order_detail.sql << 'EOF'
with cart_items as (
    select * from {{ ref('stg_checkout_success_cart_items') }}
),

rates as (
    select distinct currency_code, rate_to_usd
    from {{ ref('seed_currency_rates') }}
),

-- Danh sach key hop le trong cac dimension, dung de fallback ve -1 neu khong khop
valid_locations as (
    select location_key from {{ ref('dim_location') }}
),

valid_currencies as (
    select currency_key from {{ ref('dim_currency') }}
),

final as (
    select
        -- FIX: them item_index vao surrogate key -> dam bao duy nhat tuyet doi
        farm_fingerprint(concat(
            ci.source_event_id, '-',
            cast(ci.product_id as string), '-',
            cast(ci.item_index as string)
        )) as detail_key,

        coalesce(farm_fingerprint(ci.user_id_db), -1) as customer_key,
        coalesce(farm_fingerprint(cast(ci.product_id as string)), -1) as product_key,

        -- FIX: IP khong co trong dim_location -> gan Unknown member (-1)
        coalesce(vl.location_key, -1) as location_key,

        -- FIX: currency khong map duoc -> gan Unknown member (-1)
        coalesce(vc.currency_key, -1) as currency_key,

        coalesce(farm_fingerprint(ci.store_id), -1) as store_key,
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
    from cart_items ci
    left join rates r
        on r.currency_code = ci.currency_code
    left join valid_locations vl
        on vl.location_key = farm_fingerprint(ci.ip)
    left join valid_currencies vc
        on vc.currency_key = farm_fingerprint(ci.currency_code)
)

select * from final
EOF

echo "=========================================="
echo "Da va xong 3 loi. Chay lai: dbt build"
echo "=========================================="
