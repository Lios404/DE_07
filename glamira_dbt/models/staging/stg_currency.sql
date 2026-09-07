with source as (
    select cart_products
    from {{ source('raw_glamira', 'raw_summary') }}
    where collection = 'checkout_success' and cart_products is not null
),

symbols as (
    select distinct
        nullif(json_value(item, '$.currency'), '') as currency_symbol
    from source s,
    unnest(json_query_array(s.cart_products)) as item
)

select
    s.currency_symbol,
    coalesce(r.currency_code, 'UNK') as currency_code,
    r.currency_name
from symbols s
left join {{ ref('seed_currency_rates') }} r
    on r.currency_symbol = s.currency_symbol
