{{ config(materialized='table') }}
 
with mart_sales_order_detail_fact as (
    select * from {{ ref('fact_sales_order_detail') }}
),
mart_sales_order_detail_dim_date as (select * from {{ ref('dim_date') }}),
mart_sales_order_detail_dim_product as (select * from {{ ref('dim_product') }}),
mart_sales_order_detail_dim_location as (select * from {{ ref('dim_location') }}),
mart_sales_order_detail_dim_currency as (select * from {{ ref('dim_currency') }}),
mart_sales_order_detail_dim_store as (select * from {{ ref('dim_store') }}),
 
mart_sales_order_detail_final as (
    select
        f.detail_key,
        f.order_id,
        f.timestamp as order_timestamp,
        d.full_date,
        d.year_number,
        d.quarter_number,
        d.month_number,
        d.month_name,
        d.day_name,
        d.is_weekend,
        p.product_id,
        coalesce(p.product_name, 'Not In Catalog') as product_name,
        p.product_sku,
        coalesce(p.product_gender, 'Not In Catalog') as product_gender,
        l.location_city_name,
        l.location_region_name,
        l.location_country_name,
        l.location_country_code,
        s.store_domain,
        cur.currency_code,
        f.customer_key,
        f.sales_amount,
        cast(f.sales_local_price as float64) as sales_local_price,
        cast(f.sales_usd_price as float64) as sales_usd_price,
        cast(f.sales_amount * f.sales_usd_price as float64) as total_revenue_usd
    from mart_sales_order_detail_fact f
    left join mart_sales_order_detail_dim_date d on d.date_key = f.date_key
    left join mart_sales_order_detail_dim_product p on p.product_key = f.product_key
    left join mart_sales_order_detail_dim_location l on l.location_key = f.location_key
    left join mart_sales_order_detail_dim_currency cur on cur.currency_key = f.currency_key
    left join mart_sales_order_detail_dim_store s on s.store_key = f.store_key
)
 
select * from mart_sales_order_detail_final
