with dates as (select distinct date_key from {{ ref('dim_date') }}),
curr as (select currency_key, currency_code from {{ ref('dim_currency') }} where currency_key != -1),
rates as (select distinct currency_code, rate_to_usd from {{ ref('seed_currency_rates') }})
select
    farm_fingerprint(concat(cast(d.date_key as string), '-', c.currency_code)) as exchange_rate_key,
    d.date_key,
    c.currency_key,
    cast(r.rate_to_usd as numeric) as rate_to_usd
from dates d
cross join curr c
inner join rates r on r.currency_code = c.currency_code
