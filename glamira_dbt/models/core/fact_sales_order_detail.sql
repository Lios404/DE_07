{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['order_id', 'product_id'],
        on_schema_change='sync_all_columns'
    )
}}

with cart_items as (
    select * from {{ ref('stg_checkout_success_cart_items') }}
    {% if is_incremental() %}
        where order_date >= date_sub(current_date(), interval 3 day)
    {% endif %}
),

rates as (
    select distinct currency_code, rate_to_usd
    from {{ ref('seed_currency_rates') }}
),

valid_locations as (
    select location_key from {{ ref('dim_location') }}
),

valid_currencies as (
    select currency_key from {{ ref('dim_currency') }}
),

final as (
    select
        -- BUSINESS KEY - khong con dung Mongo _id, dung order_id (business identifier that)
        farm_fingerprint(concat(
            cast(ci.order_id as string), '-',
            cast(ci.product_id as string), '-',
            cast(ci.item_index as string)
        )) as detail_key,

        -- key phu cho join/dedupe logic theo cap order+product
        farm_fingerprint(concat(cast(ci.order_id as string), '-', cast(ci.product_id as string))) as order_product_key,

        coalesce(farm_fingerprint(ci.user_id_db), -1) as customer_key,
        coalesce(farm_fingerprint(cast(ci.product_id as string)), -1) as product_key,

        coalesce(vl.location_key, -1) as location_key,
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
    left join {{ ref('stg_location') }} loc
        on loc.ip_address = ci.ip
    left join rates r
        on r.currency_code = ci.currency_code
    left join valid_locations vl
        on vl.location_key = farm_fingerprint(concat(
            coalesce(loc.country_code, 'UNK'), '-',
            coalesce(loc.region_name, 'UNK'), '-',
            coalesce(loc.city_name, 'UNK')
        ))
    left join valid_currencies vc
        on vc.currency_key = farm_fingerprint(ci.currency_code)
)

select * from final
