select
    farm_fingerprint(ip_address) as location_key,
    city_name as location_city_name,
    region_name as location_region_name,
    country_name as location_country_name,
    country_code as location_country_code,
    current_timestamp() as inserted_date, 'dbt' as inserted_by,
    current_timestamp() as updated_date, 'dbt' as updated_by
from {{ ref('stg_ip_location') }}
union all
select -1, null, null, 'Unknown', null,
       current_timestamp(), 'dbt', current_timestamp(), 'dbt'
