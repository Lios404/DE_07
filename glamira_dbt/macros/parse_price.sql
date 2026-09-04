{% macro parse_price(price_col) %}
case
    when {{ price_col }} is null or trim({{ price_col }}) = '' then null

    -- Khong co dau phan cach: parse truc tiep
    when not regexp_contains({{ price_col }}, r'[.,]')
        then safe_cast({{ price_col }} as float64)

    -- Dau phan cach cuoi cung theo sau boi DUNG 3 chu so -> la dau ngan nghin (vd "1.185")
    when regexp_contains({{ price_col }}, r'[.,]\d{3}$')
        then safe_cast(regexp_replace({{ price_col }}, r'[.,]', '') as float64)

    -- Dau phay nam SAU dau cham -> phay la dau thap phan (dinh dang EU: "2.962,00")
    when instr({{ price_col }}, ',', -1) > instr({{ price_col }}, '.', -1)
        then safe_cast(replace(replace({{ price_col }}, '.', ''), ',', '.') as float64)

    -- Con lai: cham la dau thap phan (dinh dang US: "1,094.00")
    else safe_cast(replace({{ price_col }}, ',', '') as float64)
end
{% endmacro %}
