---
date: 2026-11-01
phase: streaming
topic: Stream branching and sidecar outputs
---

# Stream branching and sidecar outputs

*Streaming and distributed processing*

## Concept

Stream branching splits a single input stream into multiple independent processing paths, each optimized for different downstream use cases. A sidecar output is a secondary, often lower-latency or differently-structured derivative stream produced alongside the primary output—common examples include alerting streams, dead-letter queues, and feature stores that need to ingest fresh data in real time.

Without stream branching, you either duplicate the source consumption (inefficient) or force all transformations through a single bottleneck pipeline. Sidecar outputs solve the problem of needing multiple schemas or SLAs from the same raw event: your main pipeline might produce daily aggregates, but your alerts team needs anomalies within seconds, and your ML feature store needs individual records with different denormalization.

In distributed streaming systems (Kafka, Pulsar, Kinesis), branching happens at the consumer/processor level, not the broker—one topic fans out to multiple independent consumer groups or applications. This decoupling is critical: if your alerting pipeline stalls, your batch reporting shouldn't suffer.

## Practice

**Problem:** Job postings stream in real-time. You need (1) a main pipeline that aggregates salary statistics by location and title hourly, and (2) a sidecar that immediately flags any remote-work posting with salary > $200k as a "hot job" for instant notification.

```sql
-- Main stream: hourly salary aggregates
INSERT INTO job_postings_agg_hourly
SELECT 
  DATE_TRUNC('hour', job_posted_date) AS hour,
  job_location,
  job_title_short,
  COUNT(*) AS posting_count,
  AVG(salary_year_avg) AS avg_salary,
  MAX(salary_year_avg) AS max_salary
FROM job_postings_fact
GROUP BY 1, 2, 3;

-- Sidecar stream: hot jobs (low latency, high value alerts)
INSERT INTO job_postings_alerts
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location,
  CURRENT_TIMESTAMP AS alert_time,
  'HOT_REMOTE_JOB' AS alert_type
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg > 200000;
```

Both queries read the same `job_postings_fact` stream independently. The alerts table is consumed by a fast notification service; the aggregates by a dashboard. No coupling.

## Notes

- **Fanout trap:** Broadcasting to too many sidecars from one processor creates backpressure; instead, use the broker's multi-consumer-group model so each sidecar is an independent consumer.
- **Schema drift:** Sidecars often lag behind schema evolution. Use versioning or a schema registry; don't assume both pipelines stay in sync.
- **Exactly-once semantics:** Branching complicates idempotency. If your processor crashes between writing the main output and the sidecar, you may have duplicates or gaps—design for at-least-once and deduplicate downstream if needed.
- **Ordering guarantees:** Branching is partition-aware in Kafka/Pulsar. If you branch by different keys (e.g., one by location, one by title), reorder within each branch carefully.
- **Related topics:** dead-letter queues (error sidecar), change-data-capture (CDC feeds as sidecars), stream joins (when sidecars need to enrich from reference data), and backpressure handling (why branching at scale requires monitoring).
