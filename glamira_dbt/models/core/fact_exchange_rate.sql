with fact_exchange_rate_dates as (
    select distinct date_key from {{ ref('dim_date') }}
),
 
fact_exchange_rate_currencies as (
    select currency_key, currency_code
    from {{ ref('dim_currency') }}
    where currency_key != -1
),
 
fact_exchange_rate_rates as (
    select distinct currency_code, rate_to_usd
    from {{ ref('seed_currency_rates') }}
),
 
fact_exchange_rate_final as (
    select
        farm_fingerprint(concat(cast(d.date_key as string), '-', c.currency_code)) as exchange_rate_key,
        d.date_key,
        c.currency_key,
        cast(r.rate_to_usd as numeric) as rate_to_usd
    from fact_exchange_rate_dates d
    cross join fact_exchange_rate_currencies c
    inner join fact_exchange_rate_rates r on r.currency_code = c.currency_code
)
 
select * from fact_exchange_rate_final
