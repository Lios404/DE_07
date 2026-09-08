with cleaned as (
    select
        nullif(trim(ip), '') as ip_address,
        upper(nullif(trim(country_code), '')) as country_code,
        initcap(nullif(trim(country_name), '')) as country_name,
        initcap(nullif(trim(region_name), '')) as region_name,
        initcap(nullif(trim(city_name), '')) as city_name
    from {{ source('raw_glamira', 'raw_ip_location') }}
    where ip is not null
)

select distinct
    ip_address,
    case
        when country_code is null then null
        when regexp_contains(country_code, r'^[A-Z]{2}$') then country_code
        else null
    end as country_code,
    case
        when country_name is null then null
        when upper(country_name) like '%INVALID%' or upper(country_name) like '%MISSING%' or country_name = '-'
            then null
        else country_name
    end as country_name,
    case
        when region_name is null then null
        when upper(region_name) like '%INVALID%' or upper(region_name) like '%MISSING%' or region_name = '-'
            then null
        else region_name
    end as region_name,
    case
        when city_name is null then null
        when upper(city_name) like '%INVALID%' or upper(city_name) like '%MISSING%' or city_name = '-'
            then null
        else city_name
    end as city_name
from cleaned
