with source as (
    select
        _id as source_event_id,   -- giu lai chi de truy vet/debug, KHONG dung lam business key
        -- time_stamp: CAST cung theo policy - da verify 0 dong non-numeric o raw layer
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
        date(event_timestamp) as order_date,
        local_time,
        ip,
        store_id,
        user_id_db,
        email_address,
        device_id,
        user_agent,
        -- order_id: GIU SAFE_CAST - da chung minh bang du lieu that co ca
        -- "910066835" (int-string) va "3251020421.0" (float-string)
        safe_cast(safe_cast(order_id as float64) as int64) as order_id,
        -- product_id/amount trich tu JSON long - chua verify rieng ve du lieu bien dang,
        -- giu SAFE_CAST than trong (khong co bang chung sach nhung cung khong co bang chung ban)
        safe_cast(json_value(item, '$.product_id') as int64) as product_id,
        safe_cast(json_value(item, '$.amount') as int64) as amount,
        json_value(item, '$.price') as price_raw,
        nullif(json_value(item, '$.currency'), '') as currency_symbol
    from unnested
    where json_value(item, '$.product_id') is not null
),

priced as (
    select
        p.* except(price_raw, currency_symbol),
        -- macro parse_price GIU NGUYEN, khong rewrite - da chung minh dung voi EU/US format
        {{ parse_price('p.price_raw') }} as unit_price,
        cur.currency_code
    from parsed p
    left join {{ ref('stg_currency') }} cur
        on cur.currency_symbol = p.currency_symbol
),

deduplicated as (
    select *
    from priced
    -- DEDUPLICATION RULE - da xac nhan bang bang chung thuc te:
    -- order_id=5050209617 co 17 event trong ~6 phut, cung product_id/amount/price,
    -- chi khac source_event_id (Mongo _id moi moi lan) va event_timestamp.
    -- Day la duplicate tracking event o tang ingestion, khong phai 17 giao dich that.
    -- Giu ban ghi SOM NHAT (ASC) vi la thoi diem checkout that su dau tien.
    qualify row_number() over (
        partition by order_id, product_id
        order by event_timestamp asc
    ) = 1
)

select * from deduplicated
