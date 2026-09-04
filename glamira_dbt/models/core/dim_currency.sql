with distinct_codes as (
    select distinct currency_code from {{ ref('seed_currency_rates') }}
)
select
    farm_fingerprint(d.currency_code) as currency_key,
    d.currency_code,
    max(s.currency_name) as currency_name,
    current_timestamp() as inserted_date, 'dbt' as inserted_by,
    current_timestamp() as updated_date, 'dbt' as updated_by
from distinct_codes d
left join {{ ref('seed_currency_rates') }} s on s.currency_code = d.currency_code
group by d.currency_code
union all
select -1, 'UNK', 'Unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
