/* =====================================================
USER RETENTION ANALYSIS
Purpose:
Analyze user retention behavior by measuring how many
users return after their first visit over time
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
user_first_visits as (
select user_pseudo_id
  , event_date
  , min(event_date) over(partition by user_pseudo_id) as first_visit_date
from session_funnel
),
user_return_days as (
select user_pseudo_id
  , event_date
  , first_visit_date
  , date_diff(event_date, first_visit_date, day) as days_since_first_visit
from user_first_visits
),
returning_users as (
select days_since_first_visit
  , count(distinct user_pseudo_id) as users
from user_return_days
group by 1
),
retention_stats as (
select days_since_first_visit
  , users
  , first_value(users) over(order by days_since_first_visit) as initial_users
from returning_users
)
select days_since_first_visit
  , users
  , round(safe_divide(users * 100.0, initial_users), 4) as retention_rate
from retention_stats
order by days_since_first_visit;



