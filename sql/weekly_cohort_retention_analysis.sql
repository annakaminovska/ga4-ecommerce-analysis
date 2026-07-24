/* =====================================================
COHORT RETENTION ANALYSIS
Purpose:
Analyze weekly user retention by grouping users into
acquisition cohorts based on their first visit week
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
user_cohorts as (
select user_pseudo_id
  , date_trunc(first_visit_date, week(monday)) as cohort_week
  , date_trunc(event_date, week(monday)) as visit_week
from user_first_visits
),
user_retention_weeks as (
select user_pseudo_id
  , cohort_week
  , visit_week
  , date_diff(visit_week, cohort_week, week) as week_number
from user_cohorts
),
cohort_users as (
select cohort_week
  , week_number
  , count(distinct user_pseudo_id) as users
from user_retention_weeks
group by 1, 2
),
cohort_retention as (
select cohort_week
  , week_number
  , users
  , first_value(users) over(partition by cohort_week order by week_number) as initial_users
from cohort_users
)
select cohort_week
  , week_number
  , users
  , initial_users
  , round(safe_divide(users * 100.0, initial_users), 2) as weekly_retention
from cohort_retention
order by cohort_week, week_number;

