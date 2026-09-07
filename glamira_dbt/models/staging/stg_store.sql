with store_domains as (
    select
        nullif(trim(store_id), '') as store_id,
        net.host(current_url) as domain,
        count(*) as cnt
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success'
      and store_id is not null
      and current_url is not null
    group by store_id, domain
),

ranked as (
    select *,
        row_number() over (partition by store_id order by cnt desc) as rn
    from store_domains
    where store_id is not null
)

select
    store_id,
    domain as store_domain
from ranked
where rn = 1
