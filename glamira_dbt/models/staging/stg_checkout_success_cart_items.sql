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
