with dim_date_bounds as (
    select
        date(min(event_timestamp)) as min_date,
        date(max(event_timestamp)) as max_date
    from {{ ref('stg_checkout_success_cart_items') }}
),
 
dim_date_spine as (
    select date_day
    from dim_date_bounds, unnest(generate_date_array(min_date, max_date)) as date_day
),
 
dim_date_final as (
    select
        cast(format_date('%Y%m%d', date_day) as int64) as date_key,
        date_day as full_date,
        extract(dayofweek from date_day) as day_of_week,
        format_date('%A', date_day) as day_name,
        extract(day from date_day) as day_of_month,
        extract(dayofyear from date_day) as day_of_year,
        extract(week from date_day) as week_of_year,
        extract(month from date_day) as month_number,
        format_date('%B', date_day) as month_name,
        extract(quarter from date_day) as quarter_number,
        extract(year from date_day) as year_number,
        extract(dayofweek from date_day) in (1, 7) as is_weekend,
        current_timestamp() as inserted_date, 'dbt' as inserted_by,
        current_timestamp() as updated_date, 'dbt' as updated_by
    from dim_date_spine
)
 
select * from dim_date_final
