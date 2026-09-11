with dim_location_source as (
    select * from {{ ref('stg_location') }}
),
 
dim_location_distinct as (
    select distinct
        location_key,
        country_code,
        country_name,
        region_name,
        city_name
    from dim_location_source
    where location_key != -1
),
 
dim_location_final as (
    select
        location_key,
        city_name as location_city_name,
        region_name as location_region_name,
        country_name as location_country_name,
        country_code as location_country_code,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_location_distinct
 
    union all
 
    select -1, null, null, 'Unknown', null,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_location_final
