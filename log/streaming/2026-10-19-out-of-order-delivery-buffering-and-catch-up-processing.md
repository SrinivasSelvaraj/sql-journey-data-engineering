---
date: 2026-10-19
phase: streaming
topic: Out-of-order delivery: buffering and catch-up processing
---

# Out-of-order delivery: buffering and catch-up processing

*Streaming and distributed processing*

## Concept

Out-of-order delivery occurs when events arrive at a streaming system later than their actual occurrence time—a network delay might cause an event from 2 PM to arrive after an event from 2:15 PM. In distributed systems processing unbounded data streams, this is unavoidable; you cannot wait forever for stragglers before producing results.

Without handling out-of-order data, time-windowed aggregations (daily salary averages, job postings per location) produce incorrect results, state machines process events in wrong sequence, and late-arriving fact rows corrupt slowly-changing dimensions. The solution combines two strategies: **buffering** (hold incoming data for a grace period) and **catch-up processing** (recompute affected windows when late data arrives within tolerance).

The practical tension is between latency and completeness. A 24-hour buffer guarantees you catch most late arrivals but delays insights by a full day. A 5-minute buffer emits results quickly but may miss 1–2% of events. Most production systems pick a grace period (15–60 minutes) and accept that data beyond that threshold is either dropped, routed to a separate late-data handler, or triggers a full recomputation.

## Practice

**Problem:** You ingest job postings in real-time and compute daily average salaries by location. A posting from January 15 (salary $150k, location "New York") arrives on January 16 at 14:30 UTC—after the January 15 window already closed and was written to your metrics table. How do you incorporate this late data without corrupting historical results?

```sql
-- Approach: Separate late-data buffer table, then merge with recompute
CREATE TABLE job_postings_late_buffer (
  job_id INT,
  salary_year_avg INT,
  job_location VARCHAR,
  job_posted_date DATE,
  received_at TIMESTAMP,
  buffer_grace_minutes INT DEFAULT 60
);

-- On arrival, check if event is late (arrived_time > posted_date + grace period)
INSERT INTO job_postings_late_buffer
SELECT job_id, salary_year_avg, job_location, job_posted_date, NOW() as received_at, 60
FROM incoming_stream
WHERE DATEDIFF(minute, job_posted_date, CAST(NOW() AS DATE)) > 0
  AND DATEDIFF(minute, job_posted_date, CAST(NOW() AS DATE)) <= 2880; -- within 2 days

-- Recompute affected day's metric with late data included
WITH late_data AS (
  SELECT salary_year_avg, job_location, job_posted_date
  FROM job_postings_late_buffer
  WHERE job_posted_date = CAST(NOW() AS DATE) - INTERVAL 1 DAY
),
all_data AS (
  SELECT salary_year_avg, job_location, job_posted_date FROM job_postings_fact
  WHERE job_posted_date = CAST(NOW() AS DATE) - INTERVAL 1 DAY
  UNION ALL
  SELECT salary_year_avg, job_location, job_posted_date FROM late_data
)
UPDATE job_salary_metrics
SET avg_salary = (SELECT AVG(salary_year_avg) FROM all_data WHERE job_location = job_salary_metrics.job_location),
    updated_at = NOW()
WHERE metric_date = CAST(NOW() AS DATE) - INTERVAL 1 DAY;
```

## Notes

- **Common mistake:** Treating out-of-order arrival as equivalent to out-of-order event timestamps. The fix is to track both `event_time` (when it happened) and `processing_time` (when you saw it); use event_time for windowing, processing_time for grace-period logic.

- **Watermarking:** In tools like Flink and Spark Structured Streaming, watermarks signal "no events earlier than X will arrive"; they let the engine close windows confidently. Manual systems need explicit grace periods instead.

- **Idempotency is critical:** Late-arriving data often triggers recomputation. Your metrics table must support upsert or idempotent updates (e.g., by `(metric_date, job_location)` key) so recomputing the same day twice yields the same result.

- **Adjacent topic—slowly changing dimensions:** When late data affects dimension tables (e.g., a job's location changes after insertion), out-of-order handling interacts with SCD Type 2 logic; you may need to backfill dependent fact tables.

- **Revisit:** Trade-offs between real-time dashboards (tight grace periods, approximate results) and batch reconciliation jobs (daily recomputes with all data) in hybrid architectures.
