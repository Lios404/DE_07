-- Test PASS neu KHONG tra ve dong nao (chuan dbt singular test).
-- Xac nhan quy tac dedupe trong stg_checkout_success_cart_items hoat dong dung:
-- khong con cap (order_id, product_id) nao xuat hien nhieu hon 1 lan.
select order_id, product_id, count(*) as cnt
from {{ ref('stg_checkout_success_cart_items') }}
group by order_id, product_id
having count(*) > 1
