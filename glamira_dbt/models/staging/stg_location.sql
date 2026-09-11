with stg_location_cleaned as (
    select
        nullif(trim(ip), '') as ip_address,
        upper(nullif(trim(country_code), '')) as country_code,
        initcap(nullif(trim(country_name), '')) as country_name,
        initcap(nullif(trim(region_name), '')) as region_name,
        initcap(nullif(trim(city_name), '')) as city_name
    from {{ source('raw_glamira', 'raw_ip_location') }}
    where ip is not null
),
 
stg_location_name as (
    select
        ip_address,
        case
            when country_code is null then null
            when regexp_contains(country_code, r'^[A-Z]{2}$') then country_code
            else null
        end as country_code,
        case
            when country_name is null or upper(country_name) like '%INVALID%'
                 or upper(country_name) like '%MISSING%' or country_name = '-'
            then null
            else country_name
        end as country_name,
        case
            when region_name is null or upper(region_name) like '%INVALID%'
                 or upper(region_name) like '%MISSING%' or region_name = '-'
            then null
            else region_name
        end as region_name,
        case
            when city_name is null or upper(city_name) like '%INVALID%'
                 or upper(city_name) like '%MISSING%' or city_name = '-'
            then null
            else city_name
        end as city_name
    from stg_location_cleaned
),
 
stg_location_normalized as (
    select
        ip_address,
        coalesce(country_code, 'UNK') as country_code,
        coalesce(country_name, 'UNK') as country_name,
        coalesce(region_name, 'UNK') as region_name,
        coalesce(city_name, 'UNK') as city_name
    from stg_location_name
),
 
stg_location_hash_key as (
    select
        case
            when country_code = 'UNK' and region_name = 'UNK' and city_name = 'UNK' then -1
            else farm_fingerprint(country_code || '-' || region_name || '-' || city_name)
        end as location_key,
        ip_address,
        country_code,
        country_name,
        region_name,
        city_name,
        row_number() over (partition by ip_address order by ip_address) as rn
    from stg_location_normalized
)

select * except(rn) from stg_location_hash_key
where rn = 1
