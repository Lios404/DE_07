with dim_store_source as (
    select * from {{ ref('stg_store') }}
),
 
dim_store_final as (
    select
        store_key,
        cast(store_id as int64) as store_id,
        store_domain,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_store_source
 
    union all
 
    select -1, -1, 'unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_store_final
