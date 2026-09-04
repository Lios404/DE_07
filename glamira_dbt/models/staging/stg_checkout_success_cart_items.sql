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
