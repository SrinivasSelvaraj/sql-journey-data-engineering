---
date: 2026-10-19
phase: streaming
topic: Late data handling: allowed lateness and sidecar streams
---

# Late data handling: allowed lateness and sidecar streams

*Streaming and distributed processing*

## Concept

Late data handling addresses the reality that streaming systems receive records out of order and long after their event time. **Allowed lateness** sets a grace period: how long after a window closes should the system continue accepting and reprocessing records that belong to that window. Without it, a user event from 2 hours ago arriving now gets dropped silently, corrupting aggregates and KPIs. **Sidecar streams** (or side outputs) capture these late arrivals separately—either for reprocessing in batch, for monitoring data quality, or for lower-SLA dashboards. Together, they prevent the false choice between losing data and stalling real-time results.

In practice: you're computing hourly job posting counts by location. A posting event timestamped 14:00 should contribute to the 14:00–15:00 window. If it arrives at 16:30, do you ignore it (incomplete metrics), hold the result (slow dashboards), or retroactively correct it (complex orchestration)? Allowed lateness lets you emit a preliminary result at 15:00, then refine it until 15:45 (15-minute grace period). Sidecar streams let you log which records arrived late so you can measure data freshness and decide whether to backfill external systems.

## Practice

**Problem:** Track total and average salary by job location in 10-minute windows. Job posting events sometimes arrive 30+ minutes late due to API buffering. You need real-time dashboards to update within 1 minute of window close, but you also need accurate final counts for billing.

```sql
-- Simulated streaming job postings with event_time and processing_time
CREATE TEMPORARY VIEW job_events AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location,
  job_posted_date AS event_time,
  CURRENT_TIMESTAMP AS processing_time
FROM job_postings_fact;

-- Tumbling 10-minute window with 30-minute allowed lateness
SELECT 
  TUMBLE_START(event_time, INTERVAL '10' MINUTE) AS window_start,
  TUMBLE_END(event_time, INTERVAL '10' MINUTE) AS window_end,
  job_location,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  CASE 
    WHEN processing_time > TUMBLE_END(event_time, INTERVAL '10' MINUTE) + INTERVAL '1' MINUTE 
    THEN 'on_time' 
    ELSE 'late' 
  END AS arrival_status
FROM job_events
WHERE processing_time <= event_time + INTERVAL '30' MINUTE  -- allowed lateness filter
GROUP BY 
  TUMBLE_START(event_time, INTERVAL '10' MINUTE),
  TUMBLE_END(event_time, INTERVAL '10' MINUTE),
  job_location;

-- Sidecar stream: route records arriving >30min late to dead-letter queue
SELECT 
  job_id,
  job_location,
  event_time,
  processing_time,
  TIMESTAMP_DIFF(processing_time, event_time) AS lateness_seconds,
  'exceeded_grace_period' AS rejection_reason
FROM job_events
WHERE processing_time > event_time + INTERVAL '30' MINUTE;
```

## Notes

- **Allowed lateness tuning:** Too short and you lose data; too long and you emit redundant updates. Start conservative (match your SLA requirement), then measure actual lateness percentiles to optimize.
- **Sidecar vs. retry logic:** Sidecar streams are observability and recourse, not a replacement for retries. Late data should still flow into the main aggregation if within the grace period—sidecars capture only what *exceeds* it.
- **Watermarks and out-of-order arrival:** Allowed lateness works within a watermarking system (Kafka Streams, Flink, BigQuery Streaming). The watermark signals "no events earlier than time X will arrive"; lateness grace extends past that. Conflate these and you'll either drop valid data or never close windows.
- **Backfill strategy:** Sidecar records should be replayable through batch jobs (e.g., Spark on the dead-letter queue) to correct downstream fact tables. Otherwise you document the error but never fix it.
- **Cost trade-off:** Each sidecar record requires storage, monitoring, and reprocessing logic. Document why you're keeping it (e.g., "late job postings update salary benchmarks") to avoid indefinite accumulation.
