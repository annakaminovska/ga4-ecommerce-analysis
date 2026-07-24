/* =====================================================
HIGH-INTENT USER SEGMENTATION ANALYSIS
Purpose:
Evaluate whether returning high-intent users
generate more revenue and convert better than
one-time visitors
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
-- Create unique session identifiers
events_with_session as (
select *
  , concat(user_pseudo_id, '_', cast(ga_session_id as string)) as unique_session_id
  , date(event_timestamp) as event_date
from raw_events
),
-- Aggregate event-level data into session-level funnel metrics
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
-- Segment users based on the number of sessions
user_segments as (
select user_pseudo_id
  , case when count(distinct unique_session_id) = 1 then 'One-time' else 'Returning' end as user_type
from session_funnel
group by 1
),
-- Keep only users who reached the checkout stage
high_intent_users as (
select us.user_pseudo_id
  , us.user_type
  , sf.begin_checkout
  , sf.purchase
  , sf.revenue
from user_segments us
join session_funnel sf
on us.user_pseudo_id = sf.user_pseudo_id
where begin_checkout = 1
)
select user_type
  , count(distinct user_pseudo_id) as users
  , count(distinct case when purchase = 1 then user_pseudo_id end) as purchasers
  , round(safe_divide(
      count(distinct case when purchase = 1 then user_pseudo_id end), 
      count(distinct user_pseudo_id)
    ), 2) as purchase_rate
  , sum(revenue) as total_revenue
  , round(sum(revenue) / count(distinct user_pseudo_id), 2) as revenue_per_user
from high_intent_users
group by 1;
