with stg_store_domains as (
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
 
stg_store_ranked as (
    select *,
        row_number() over (partition by store_id order by cnt desc) as rn
    from stg_store_domains
),
 
stg_store_top_domain as (
    select store_id, domain as store_domain
    from stg_store_ranked
    where rn = 1
),
 
stg_store_hash_key as (
    select
        farm_fingerprint(store_id) as store_key,
        store_id,
        store_domain
    from stg_store_top_domain
)
 
select * from stg_store_hash_key
