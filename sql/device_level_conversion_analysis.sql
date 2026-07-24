/* ===========================================================
DEVICE-LEVEL FUNNEL ANALYSIS
Purpose:
Analyze funnel conversion performance across device categories
Used to compare user behavior and purchase intent by device
============================================================*/

-- Extract and clean raw GA4 event data
with raw_events as (
select event_name
  , user_pseudo_id
  , timestamp_micros(event_timestamp) as event_timestamp
  , (select value.int_value from unnest(event_params) where key = 'ga_session_id')  as ga_session_id
  , traffic_source.source           as traffic_source
  , traffic_source.medium           as traffic_medium
  , device.category                 as device_category
  , ecommerce.transaction_id        as transaction_id
  , ecommerce.purchase_revenue      as purchase_revenue
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
), 
-- Create unique session identifiers and order events within sessions
events_with_session as (
select *
  , concat(user_pseudo_id, '_', cast(ga_session_id as string)) as unique_session_id
  , date(event_timestamp) as event_date
from raw_events
),
-- Aggregate event-level data into session-level funnel flags
session_funnel as (
select unique_session_id
  , user_pseudo_id
  , event_date
  , traffic_source
  , traffic_medium
  , device_category
  , max(case when event_name = 'session_start' then 1 else 0 end)  as session_start
  , max(case when event_name = 'view_item' then 1 else 0 end)      as view_item
  , max(case when event_name = 'add_to_cart' then 1 else 0 end)    as add_to_cart
  , max(case when event_name = 'begin_checkout' then 1 else 0 end) as begin_checkout
  , max(case when event_name = 'purchase' then 1 else 0 end)       as purchase
  , sum(coalesce(purchase_revenue, 0)) as revenue
  , count(*) as total_events_in_session
from events_with_session
group by 1, 2, 3, 4, 5, 6
)
-- Compare funnel performance metrics across device categories
select device_category
  , count(*)            as total_sessions
  , sum(view_item)      as sessions_with_product_view
  , round(safe_divide(sum(view_item), count(*)), 2)              as product_view_rate
  , sum(add_to_cart)    as sessions_with_cart
  , round(safe_divide(sum(add_to_cart), sum(view_item)), 2)      as add_to_cart_rate
  , sum(begin_checkout) as sessions_with_checkout
  , round(safe_divide(sum(begin_checkout), sum(add_to_cart)), 2) as checkout_rate
  , sum(purchase)       as sessions_with_purchase
  , round(safe_divide(sum(purchase), sum(begin_checkout)), 2)    as purchase_rate
  , sum(revenue)        as total_revenue
  , round(safe_divide(sum(revenue), count(*)), 2)                as revenue_per_session
from session_funnel
group by 1;


