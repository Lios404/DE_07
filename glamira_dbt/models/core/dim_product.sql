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
