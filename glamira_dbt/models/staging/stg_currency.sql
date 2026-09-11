with stg_currency_source as (
    select cart_products
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success' and cart_products is not null
),
 
stg_currency_symbols as (
    select distinct
        nullif(json_value(item, '$.currency'), '') as currency_symbol
    from stg_currency_source s,
    unnest(json_query_array(s.cart_products)) as item
),
 
stg_currency_mapped as (
    select
        s.currency_symbol,
        coalesce(r.currency_code, 'UNK') as currency_code,
        r.currency_name
    from stg_currency_symbols s
    left join {{ ref('seed_currency_rates') }} r
        on r.currency_symbol = s.currency_symbol
),
 
stg_currency_hash_key as (
    select
        case
            when currency_code = 'UNK' then -1
            else farm_fingerprint(currency_code)
        end as currency_key,
        currency_symbol,
        currency_code,
        currency_name
    from stg_currency_mapped
)
 
select * from stg_currency_hash_key
