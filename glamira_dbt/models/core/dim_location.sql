with normalized as (
    select
        coalesce(country_code, 'UNK') as country_code,
        coalesce(region_name, 'UNK') as region_name,
        coalesce(city_name, 'UNK') as city_name,
        country_name
    from {{ ref('stg_location') }}
),

distinct_locations as (
    select
        country_code,
        region_name,
        city_name,
        any_value(country_name) as country_name
    from normalized
    -- Loai to hop toan UNK khoi nhom "that" - danh rieng cho Unknown member (-1)
    where not (country_code = 'UNK' and region_name = 'UNK' and city_name = 'UNK')
    group by country_code, region_name, city_name
),

final as (
    select
        farm_fingerprint(concat(country_code, '-', region_name, '-', city_name)) as location_key,
        city_name as location_city_name,
        region_name as location_region_name,
        country_name as location_country_name,
        country_code as location_country_code,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from distinct_locations

    union all

    select -1, null, null, 'Unknown', null,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)

select * from final
