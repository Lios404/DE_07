with store_domains as (
    select store_id, net.host(current_url) as domain, count(*) as cnt
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success' and store_id is not null and current_url is not null
    group by store_id, domain
),
ranked as (
    select *, row_number() over (partition by store_id order by cnt desc) as rn
    from store_domains
)
select
    farm_fingerprint(store_id) as store_key,
    safe_cast(store_id as int64) as store_id,
    domain as store_domain,
    current_timestamp() as inserted_date, 'dbt' as inserted_by,
    current_timestamp() as updated_date, 'dbt' as updated_by
from ranked where rn = 1
union all
select -1, -1, 'unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
