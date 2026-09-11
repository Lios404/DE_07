with dim_currency_source as (
    select * from {{ ref('stg_currency') }}
),
 
dim_currency_distinct as (
    select distinct
        currency_key,
        currency_code,
        currency_name
    from dim_currency_source
    where currency_key != -1
),
 
dim_currency_final as (
    select
        currency_key,
        currency_code,
        currency_name,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_currency_distinct
 
    union all
 
    select -1, 'UNK', 'Unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_currency_final
