---
date: 2026-08-15
phase: streaming
topic: Event time vs processing time
---

# Event time vs processing time

*Streaming and distributed processing*

## Concept

**Event time** is when something actually happened in the real world (e.g., a user clicked a button, a sensor recorded a reading); **processing time** is when your system observes and processes that event. In streaming systems, these two are almost never the same. A mobile app may record a click offline, then upload it hours later. A sensor may buffer data and batch-send it. Network delays, system failures, and out-of-order delivery mean processing time is unreliable for truth.

This distinction matters because aggregations drift without it. If you count "jobs posted today" by processing time, you'll miscount jobs posted late and processed the next calendar day. Windowing operations become meaningless—a 1-hour rolling window by processing time captures a chaotic mix of events from different real hours. Exactly-once semantics, late-arriving data, and replayability all depend on anchoring logic to event time.

Without explicit event time handling, your metrics become non-deterministic and audit-proof. Replaying data produces different results. Late-arriving facts corrupt historical aggregates. This is why data warehouses and streaming frameworks (Kafka, Spark, Flink) treat event time as a first-class citizen.

## Practice

**Problem:** You need to calculate the average salary of jobs posted in each calendar day, and you must handle jobs whose records arrive late (e.g., a job posted on Jan 1 but received in your system on Jan 3).

```sql
SELECT
  DATE(job_posted_date) AS posting_day,
  COUNT(*) AS jobs_posted,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY DATE(job_posted_date)
ORDER BY posting_day DESC;
```

This query groups by **event time** (`job_posted_date`), not the timestamp when the row was inserted. Even if a job record arrives three days late, it correctly attributes the event to its actual posting day. Without this, using a `created_at` or `ingested_at` column would misplace late jobs into the wrong day's aggregate.

## Notes

- **Common mistake:** Confusing `CURRENT_TIMESTAMP` (processing time) with the business-meaningful timestamp. Queries that use `WHERE ingested_at > NOW()` capture only freshly arrived data, not data from a specific real-world period.
- **Watermarking:** In streaming engines, a watermark tells you "all events before time X have arrived." Use it to decide when to close a window and emit results; without it, you wait forever for stragglers.
- **Idempotency & late data:** If you allow late-arriving facts, design your pipeline to recompute affected windows. Many systems use a `_scd_type_2` or append-only log to track corrections.
- **Adjacent topics:** Session windows (group events by inactivity, not clock time), allowed lateness (how long to buffer before closing), and Lambda/Kappa architectures (batch + stream reconciliation).
- **Revisit:** How your data warehouse updates late-arriving dimensions (slowly changing dimensions) and how to handle out-of-order microbatches in near-real-time systems.
