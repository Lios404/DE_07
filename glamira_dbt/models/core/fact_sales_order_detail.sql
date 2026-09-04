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
