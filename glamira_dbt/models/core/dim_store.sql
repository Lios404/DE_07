with final as (
    select
        farm_fingerprint(store_id) as store_key,
        cast(store_id as int64) as store_id,
        store_domain,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from {{ ref('stg_store') }}

    union all

    select -1, -1, 'unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)

select * from final
