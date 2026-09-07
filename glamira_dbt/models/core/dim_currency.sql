with real_currencies as (
    select
        currency_code,
        any_value(currency_name) as currency_name
    from {{ ref('stg_currency') }}
    where currency_code != 'UNK'   -- loai UNK khoi nhom that, danh rieng cho Unknown member ben duoi
    group by currency_code
),

final as (
    select
        farm_fingerprint(currency_code) as currency_key,
        currency_code,
        currency_name,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from real_currencies

    union all

    select -1, 'UNK', 'Unknown', current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)

select * from final
