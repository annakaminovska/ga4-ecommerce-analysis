/* ==================================================================
POST-PRODUCT VIEW BEHAVIOR ANALYSIS
Purpose:
Analyze the immediate next actions users take after viewing a product
Used for behavioral flow and drop-off analysis
===================================================================*/

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
-- Enrich events with the next user action within each session
event_sequence as (
select *
  , lead(event_name) over(partition by unique_session_id order by event_timestamp) as next_event
from events_with_session
)
-- Analyze the most common actions taken after product views
select next_event
  , count(*) as occurrences
from event_sequence
where event_name = 'view_item'
group by 1
order by 2 desc;





