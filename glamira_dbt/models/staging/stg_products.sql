with source as (
    select
        product_id,
        name as product_name,
        sku as product_sku,
        gender,
        price,
        min_price,
        max_price
    from {{ source('raw_glamira', 'raw_products') }}
),

cleaned as (
    select
        -- Chua co bang chung product_id bi sai dinh dang -> CAST theo policy
        cast(product_id as int64) as product_id,
        nullif(trim(product_name), '') as product_name,
        nullif(trim(product_sku), '') as product_sku,

        -- GENDER NORMALIZATION - dua tren 22 gia tri distinct THAT da xac nhan bang query,
        -- khong doan mo. Cac ngon ngu chau Au deu la bien the cua "phu nu".
        case
            when gender is null or trim(gender) = '' then 'Unknown'
            when lower(trim(gender)) in (
                'women', 'female', 'femelle', 'femeie', 'kadın', 'mujer', 'női',
                'frauen', 'sieviete', 'vrouw', 'женски', 'donna', 'kvinne',
                'naine', 'nainen', 'žena', 'ženski'
            ) then 'Female'
            when lower(trim(gender)) = 'men' then 'Male'
            when lower(trim(gender)) in ('kids', 'çocuk') then 'Kids'
            else 'Unknown'  -- gia tri chua xac dinh -> Unknown, khong xoa record
        end as product_gender,

        -- Chua verify rieng ve du lieu bien dang cho price -> giu SAFE_CAST than trong
        safe_cast(price as numeric) as product_base_price,
        safe_cast(min_price as numeric) as product_min_price,
        safe_cast(max_price as numeric) as product_max_price
    from source
    where product_id is not null
)

select * from cleaned
