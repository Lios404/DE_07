select distinct
    nullif(trim(ip), '') as ip_address,
    nullif(trim(country_code), '') as country_code,
    nullif(trim(country_name), '') as country_name,
    nullif(trim(region_name), '') as region_name,
    nullif(trim(city_name), '') as city_name
from {{ source('raw_glamira', 'raw_ip_location') }}
where ip is not null
