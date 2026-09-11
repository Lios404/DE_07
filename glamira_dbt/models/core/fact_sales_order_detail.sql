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
    select currency_key, currency_code from {{ ref('dim_currency') }} where currency_key != -1
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
