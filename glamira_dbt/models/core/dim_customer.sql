with dim_customer_checkout as (
    select * from {{ ref('stg_checkout_success_cart_items') }}
    where user_id_db is not null
),
 
dim_customer_ranked as (
    select
        customer_key,
        user_id_db,
        device_id,
        user_agent,
        email_address,
        row_number() over (partition by customer_key order by event_timestamp desc) as rn,
        min(date(event_timestamp)) over (partition by customer_key) as first_seen_date
    from dim_customer_checkout
),
 
dim_customer_final as (
    select
        customer_key,
        user_agent as customer_user_agent,
        user_id_db as customer_user_id_db,
        device_id as customer_device_id,
        to_hex(sha256(lower(trim(email_address)))) as customer_email_address,
        first_seen_date as start_date,
        cast(null as date) as end_date,
        true as is_current,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_customer_ranked
    where rn = 1
 
    union all
 
    select -1, null, 'UNKNOWN', null, null, null, null, true,
           current_timestamp(), 'dbt', current_timestamp(), 'dbt'
)
 
select * from dim_customer_final
