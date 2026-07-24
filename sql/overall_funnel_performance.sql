/* =====================================================
SESSION-LEVEL FUNNEL MODEL
Purpose:
Build a behavioral funnel table with 1 row per session
Used for conversion and drop-off analysis
======================================================*/

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
),
-- Calculate overall funnel metrics
funnel_metrics as (
select count(*) as total_sessions
  , sum(session_start)          as sessions_started
  , sum(view_item)              as sessions_with_product_view
  , sum(add_to_cart)            as sessions_with_cart
  , sum(begin_checkout)         as sessions_with_checkout
  , sum(purchase)               as sessions_with_purchase
from session_funnel
), 
-- Calculate conversion rates between funnel stages
funnel_cr as (
select 'session_start' as funnel_stage
  , sessions_started as sessions
  , 1.0 as conversion_rate
  , 1 as stage_order
from funnel_metrics

union all

select 'view_item' as funnel_stage
  , sessions_with_product_view as sessions
  , round(safe_divide(sessions_with_product_view, sessions_started), 2) as conversion_rate
  , 2 as stage_order
from funnel_metrics

union all

select 'add_to_cart' as funnel_stage
  , sessions_with_cart as sessions
  , round(safe_divide(sessions_with_cart, sessions_with_product_view), 2) as conversion_rate
  , 3 as stage_order
from funnel_metrics

union all

select 'begin_checkout' as funnel_stage
  , sessions_with_checkout as sessions
  , round(safe_divide(sessions_with_checkout, sessions_with_cart), 2) as conversion_rate
  , 4 as stage_order
from funnel_metrics

union all

select 'purchase' as funnel_stage
  , sessions_with_purchase as sessions
  , round(safe_divide(sessions_with_purchase, sessions_with_checkout), 2) as conversion_rate
  , 5 as stage_order
from funnel_metrics
)
select funnel_stage, sessions, conversion_rate
from funnel_cr
order by stage_order;
