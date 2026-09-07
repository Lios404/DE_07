{{ config(materialized='table') }}

with fact as (
    select * from {{ ref('fact_sales_order_detail') }}
),
d as (select * from {{ ref('dim_date') }}),
p as (select * from {{ ref('dim_product') }}),
l as (select * from {{ ref('dim_location') }}),
cur as (select * from {{ ref('dim_currency') }}),
s as (select * from {{ ref('dim_store') }})

select
    f.detail_key,
    f.order_id,
    f.timestamp as order_timestamp,

    -- Time-based trends
    d.full_date,
    d.year_number,
    d.quarter_number,
    d.month_number,
    d.month_name,
    d.day_name,
    d.is_weekend,

    -- Product performance
    p.product_id,
    coalesce(p.product_name,'Not In Catalog') as product_name,
    p.product_sku,
    p.product_gender,

    -- Geographic distribution
    l.location_city_name,
    l.location_region_name,
    l.location_country_name,
    l.location_country_code,

    -- Store / currency context
    s.store_domain,
    cur.currency_code,

    -- Customer (khong lo email/PII, chi giu key giu danh)
    f.customer_key,

    -- Revenue analysis (measures)
    f.sales_amount,
    cast(f.sales_local_price as float64) as sales_local_price,
    cast(f.sales_usd_price as float64) as sales_usd_price,
    cast(f.sales_amount * f.sales_usd_price as float64) as total_revenue_usd
from fact f
left join d on d.date_key = f.date_key
left join p on p.product_key = f.product_key
left join l on l.location_key = f.location_key
left join cur on cur.currency_key = f.currency_key
left join s on s.store_key = f.store_key
