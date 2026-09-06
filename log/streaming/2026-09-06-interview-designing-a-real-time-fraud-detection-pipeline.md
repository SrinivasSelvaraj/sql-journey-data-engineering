---
date: 2026-09-06
phase: streaming
topic: Interview: designing a real-time fraud detection pipeline
---

# Interview: designing a real-time fraud detection pipeline

*Streaming and distributed processing*

## Concept

Real-time fraud detection in streaming requires processing transaction or event data *as it arrives*, without waiting for a complete batch. Unlike batch jobs that process yesterday's data today, fraud detection must flag suspicious patterns within milliseconds—chargebacks and reversals compound over time. The challenge is that events arrive out-of-order (a refund may appear before its original transaction), late (network delays), and in high volume (millions/second at scale), making windowing, state management, and exactly-once semantics critical.

Without proper streaming architecture, you either accept latency (batch = fraud already posted) or lose accuracy (dropping out-of-order events). A typical pipeline buffers raw events → applies stateful rules (velocity checks: 5 transactions in 10 seconds?) → joins against reference data (known-bad IPs, blocked merchants) → emits alerts with low false-positive rates. The system must handle reprocessing (exactly-once semantics) and gracefully degrade when late events or out-of-order arrivals would break determinism.

## Practice

**Problem:** Design a real-time alert for job posting spam. Flag a recruiter if they post more than 10 jobs with `salary_year_avg > $200k` within a 1-hour sliding window. Include the recruiter ID (infer from `job_posted_date` and `job_location` clustering), job count, and earliest alert timestamp.

```sql
-- Streaming job posting fraud detection
WITH job_events AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,
    job_location,
    -- Mock recruiter_id from location; in practice, from upstream event
    CAST(FARM_FINGERPRINT(job_location) AS INT64) AS recruiter_id,
    CURRENT_TIMESTAMP() AS event_time
  FROM job_postings_fact
  WHERE salary_year_avg > 200000
),
windowed AS (
  SELECT 
    recruiter_id,
    job_posted_date,
    COUNT(*) OVER (
      PARTITION BY recruiter_id 
      ORDER BY UNIX_TIMESTAMP(job_posted_date) 
      RANGE BETWEEN 3600 PRECEDING AND CURRENT ROW
    ) AS jobs_in_1hr,
    MIN(job_posted_date) OVER (
      PARTITION BY recruiter_id 
      ORDER BY UNIX_TIMESTAMP(job_posted_date) 
      RANGE BETWEEN 3600 PRECEDING AND CURRENT ROW
    ) AS window_start,
    ROW_NUMBER() OVER (
      PARTITION BY recruiter_id 
      ORDER BY job_posted_date
    ) AS event_seq
  FROM job_events
)
SELECT 
  recruiter_id,
  jobs_in_1hr,
  window_start,
  CURRENT_TIMESTAMP() AS alert_time,
  'HIGH_VOLUME_POSTING' AS alert_type
FROM windowed
WHERE jobs_in_1hr > 10
  AND event_seq = jobs_in_1hr;  -- emit alert only when threshold first crossed
```

## Notes

- **Watermarking matters:** define when you stop accepting late events. A watermark 5 minutes behind means events after that are dropped; tune based on SLA vs. completeness trade-off.
- **State explosion:** holding state (counts, aggregates) for every user/merchant indefinitely breaks memory. Use TTL (time-to-live) to age out inactive keys.
- **Out-of-order reordering:** Kafka/Pulsar do *not* guarantee order across partitions; if fraud rules depend on causality (refund *after* charge), use event timestamps + session windows, not message arrival order.
- **Adjacent topics:** exactly-once semantics (idempotent sinks, deduplication windows), joining streams to reference tables (enrichment), and backpressure/flow control to avoid queue overflow.
- **Common mistake:** treating stream processing like batch—no, you cannot re-run the 1-hour window retroactively once an event arrives late; decide upfront whether late events update past alerts or are sidelined.
