-- Test PASS neu KHONG tra ve dong nao.
-- Xac nhan mart_sales_order_detail khong bi nhan doi/mat dong so voi fact
-- (co the xay ra neu 1 dimension nao do vo tinh co key trung lap).
with counts as (
    select
        (select count(*) from {{ ref('fact_sales_order_detail') }}) as fact_count,
        (select count(*) from {{ ref('mart_sales_order_detail') }}) as mart_count
)
select *
from counts
where fact_count != mart_count
