# Schema Discovery Report

- Tổng số collection: **27**
- Tổng số field (union toàn bộ collection): **60**

## Master field list (union tất cả collection)

| Field path | Observed type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cart_products | array |
| cart_products[] | object |
| cart_products[].amount | int |
| cart_products[].currency | string |
| cart_products[].option | array, string |
| cart_products[].option[] | object |
| cart_products[].option[].option_id | int |
| cart_products[].option[].option_label | string |
| cart_products[].option[].value_id | int |
| cart_products[].option[].value_label | string |
| cart_products[].price | string |
| cart_products[].product_id | int |
| cat_id | null |
| collect_id | string |
| collection | string |
| currency | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| is_paypal | null |
| key_search | null, string |
| local_time | string |
| option | array, object |
| option.Kollektion | string |
| option.alloy | string |
| option.category id | string |
| option.diamond | string |
| option.finish | string |
| option.kollektion_id | string |
| option.pearlcolor | string |
| option.price | string |
| option.shapediamond | string |
| option.stone | string |
| option[] | object |
| option[].option_id | string |
| option[].option_label | string |
| option[].quality | string |
| option[].quality_label | string |
| option[].value_id | string |
| option[].value_label | string |
| order_id | float, int, string |
| price | string |
| product_id | string |
| recommendation | bool |
| recommendation_clicked_position | int, null |
| recommendation_product_id | null, string |
| recommendation_product_position | int, string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |
| utm_medium | bool |
| utm_source | bool |
| viewing_product_id | string |

## Chi tiết theo từng collection

### `add_to_cart_action` (25 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| currency | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| is_paypal | null |
| local_time | string |
| option | array |
| option[] | object |
| option[].option_id | string |
| option[].option_label | string |
| option[].value_id | string |
| option[].value_label | string |
| price | string |
| product_id | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `back_to_product_action` (16 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| product_id | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `checkout` (26 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cart_products | array |
| cart_products[] | object |
| cart_products[].amount | int |
| cart_products[].option | array, string |
| cart_products[].option[] | object |
| cart_products[].option[].option_id | int |
| cart_products[].option[].option_label | string |
| cart_products[].option[].value_id | int |
| cart_products[].option[].value_label | string |
| cart_products[].product_id | int |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| order_id | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `checkout_success` (28 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cart_products | array |
| cart_products[] | object |
| cart_products[].amount | int |
| cart_products[].currency | string |
| cart_products[].option | array, string |
| cart_products[].option[] | object |
| cart_products[].option[].option_id | int |
| cart_products[].option[].option_label | string |
| cart_products[].option[].value_id | int |
| cart_products[].option[].value_label | string |
| cart_products[].price | string |
| cart_products[].product_id | int |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| order_id | float, int |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `landing_page_recommendation_clicked` (17 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| recommendation_product_id | string |
| recommendation_product_position | int |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `landing_page_recommendation_noticed` (15 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `landing_page_recommendation_visible` (15 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `listing_page_recommendation_clicked` (23 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cat_id | null |
| collect_id | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | object |
| option.alloy | string |
| option.diamond | string |
| option.shapediamond | string |
| recommendation_clicked_position | null |
| recommendation_product_id | null |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `listing_page_recommendation_noticed` (21 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cat_id | null |
| collect_id | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | object |
| option.alloy | string |
| option.diamond | string |
| option.shapediamond | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `listing_page_recommendation_visible` (21 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cat_id | null |
| collect_id | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | object |
| option.alloy | string |
| option.diamond | string |
| option.shapediamond | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `product_detail_recommendation_clicked` (18 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| recommendation_clicked_position | int |
| recommendation_product_id | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |
| viewing_product_id | string |

### `product_detail_recommendation_noticed` (16 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |
| viewing_product_id | string |

### `product_detail_recommendation_visible` (16 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |
| viewing_product_id | string |

### `product_view_all_recommend_clicked` (18 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| recommendation_product_id | string |
| recommendation_product_position | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |
| viewing_product_id | string |

### `search_box_action` (16 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| key_search | null, string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `select_product_option` (22 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | array |
| option[] | object |
| option[].option_id | string |
| option[].option_label | string |
| option[].value_id | string |
| option[].value_label | string |
| product_id | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `select_product_option_quality` (24 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | array |
| option[] | object |
| option[].option_id | string |
| option[].option_label | string |
| option[].quality | string |
| option[].quality_label | string |
| option[].value_id | string |
| option[].value_label | string |
| product_id | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `sorting_relevance_click_action` (17 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| recommendation_product_id | string |
| recommendation_product_position | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_all_recommend` (25 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | object |
| option.Kollektion | string |
| option.alloy | string |
| option.category id | string |
| option.finish | string |
| option.kollektion_id | string |
| option.pearlcolor | string |
| option.price | string |
| option.stone | string |
| product_id | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_home_page` (15 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_landing_page` (15 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_listing_page` (21 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cat_id | null |
| collect_id | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | object |
| option.alloy | string |
| option.diamond | string |
| option.shapediamond | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_my_account` (15 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_product_detail` (25 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | array |
| option[] | object |
| option[].option_id | string |
| option[].option_label | string |
| option[].value_id | string |
| option[].value_label | string |
| product_id | string |
| recommendation | bool |
| referrer_url | string |
| resolution | string |
| show_recommendation | null, string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |
| utm_medium | bool |
| utm_source | bool |

### `view_shopping_cart` (24 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| cart_products | array |
| cart_products[] | object |
| cart_products[].option | array |
| cart_products[].option[] | object |
| cart_products[].option[].option_id | int |
| cart_products[].option[].option_label | string |
| cart_products[].option[].value_id | int |
| cart_products[].option[].value_label | string |
| cart_products[].product_id | int |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_sorting_relevance` (19 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| option | object |
| option.alloy | string |
| option.diamond | string |
| option.shapediamond | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |

### `view_static_page` (15 field)

| Field path | Type(s) |
|---|---|
| _id | ObjectId |
| api_version | string |
| collection | string |
| current_url | string |
| device_id | string |
| email_address | string |
| ip | string |
| local_time | string |
| referrer_url | string |
| resolution | string |
| show_recommendation | string |
| store_id | string |
| time_stamp | int |
| user_agent | string |
| user_id_db | string |
