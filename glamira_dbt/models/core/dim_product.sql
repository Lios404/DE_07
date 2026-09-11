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
