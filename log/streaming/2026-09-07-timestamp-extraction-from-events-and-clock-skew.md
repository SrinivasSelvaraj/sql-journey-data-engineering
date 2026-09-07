---
date: 2026-09-07
phase: streaming
topic: Timestamp extraction from events and clock skew
---

# Timestamp extraction from events and clock skew

*Streaming and distributed processing*

## Concept

Timestamp extraction is the process of identifying the event time (when something actually happened) versus the processing time (when your system observed it). In streaming systems, events arrive out of order and with unpredictable delays. Clock skew—differences in time between distributed systems—compounds this problem: two servers may disagree on "now" by seconds or minutes, causing the same event to have different timestamps depending on which node processed it first.

Without proper timestamp handling, you'll compute incorrect aggregates. A user action that occurred at 2:00 PM might arrive at your stream processor at 2:15 PM due to network delay, yet another action from 2:10 PM might arrive first because it took a faster route. If you use processing time instead of event time, your counts per hour become meaningless, your fraud detection flags legitimate transactions, and your dashboards contradict reality.

The core practice is: extract the event timestamp from the payload itself (not from system clocks), validate it against reasonable bounds, and use it consistently for all windowed operations. Clock skew is managed through NTP synchronization on infrastructure and defensive programming (allowing reasonable watermark delays and out-of-order tolerance).

## Practice

**Problem:** You need to report the count of job postings per day, but postings arrive in your stream 1–2 days late due to API polling delays. If you count by the day a posting arrived in your system, your daily report will show jobs posted on Tuesday appearing on Thursday's count.

```sql
-- Extract event time from the payload, not system time
WITH extracted_timestamps AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,  -- This is the event timestamp from the source
    CAST(job_posted_date AS TIMESTAMP) AS event_time,
    CURRENT_TIMESTAMP AS processing_time
  FROM job_postings_fact
  WHERE job_posted_date IS NOT NULL
    AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY  -- Defensive: reject extreme outliers
),
daily_counts AS (
  SELECT
    DATE(event_time) AS posted_day,
    COUNT(*) AS posting_count,
    COUNT(CASE WHEN job_work_from_home THEN 1 END) AS remote_count
  FROM extracted_timestamps
  GROUP BY DATE(event_time)
)
SELECT
  posted_day,
  posting_count,
  remote_count
FROM daily_counts
ORDER BY posted_day DESC;
```

## Notes

- **Confuse event time with processing time:** This is the #1 mistake in streaming analytics. Always extract and store the source timestamp; never rely on `NOW()` or system arrival time for business logic.
- **Ignore clock skew in validation:** Set realistic bounds on acceptable event times (e.g., reject timestamps more than 7 days in the past or any in the future) to catch poisoned data and misconfigured clocks early.
- **Watermarking and late data:** Understand that stream processors use watermarks to decide when a time window is "complete." Allow a grace period (e.g., 1 hour) for late arrivals to be included in the correct window rather than discarded.
- **Timezone handling:** Event timestamps should be stored in UTC and normalized at ingestion; applying timezone logic downstream causes subtle bugs across time zone boundaries.
- **Related patterns:** See also stateful stream processing (sessionization), out-of-order tolerance windows, and event sourcing architectures that treat the timestamp as immutable metadata.
