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
