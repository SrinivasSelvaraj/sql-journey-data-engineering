---
date: 2026-09-26
phase: streaming
topic: Rebalancing and stop-the-world pauses in groups
---

# Rebalancing and stop-the-world pauses in groups

*Streaming and distributed processing*

## Concept

Rebalancing occurs when a consumer group in a distributed streaming system (like Kafka) must redistribute partitions among members—triggered by a consumer joining/leaving, a broker failure, or a manual trigger. During rebalancing, a **stop-the-world pause** halts all consumption and processing until the new partition assignment is committed and members resume. This pause introduces latency, can cause duplicate or out-of-order message processing if offsets aren't managed carefully, and becomes critical in low-latency systems (fraud detection, real-time bidding) where even 10–30 second pauses are unacceptable.

Without proper rebalancing, orphaned partitions go unconsumed, new consumers starve, and offset tracking becomes inconsistent—leading to data loss or reprocessing. The pause is necessary for safety: it prevents one consumer from reading an offset while another has already committed it, which would create an inconsistent state.

## Practice

**Problem:** A real-time job posting ingestion pipeline consumes from Kafka (10 partitions, 3 consumers). During peak ingestion, you need to add a fourth consumer to handle increased salary aggregation load, but the rebalance pause is causing a 45-second lag spike that breaks your dashboard SLA. Design a consumption and offset management strategy to minimize pause impact.

```sql
-- Offset commit strategy: commit synchronously only after aggregation completes
-- (In application code / Kafka config, not pure SQL, but shown as pseudo-config)

-- 1. Set smaller rebalance timeout & heartbeat to fail fast on dead consumers
-- session.timeout.ms = 6000 (default 10s)
-- heartbeat.interval.ms = 2000 (default 3s)

-- 2. Use incremental cooperative rebalancing (not stop-the-world full rebalance)
-- partition.assignment.strategy = "cooperative-sticky"

-- 3. Pre-aggregate in-flight data before committing offset
SELECT 
  DATE_TRUNC('minute', job_posted_date) AS minute_bucket,
  COUNT(*) AS job_count,
  AVG(salary_year_avg) AS avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_count,
  MAX(job_posted_date) AS latest_ingestion_time
FROM job_postings_fact
WHERE job_posted_date >= NOW() - INTERVAL '1 minute'
GROUP BY DATE_TRUNC('minute', job_posted_date)
-- Commit offset only *after* this aggregation lands in destination system
```

## Notes

- **Cooperative rebalancing** (vs. eager) lets existing consumers keep some partitions while only reassigning others—reducing pause to milliseconds instead of seconds.
- **Over-aggressive offset commits** (every message) hurt throughput; **under-committing** risks reprocessing after failure—find balance via `auto.commit.interval.ms` and manual commit placement after processing.
- **Rebalance listener patterns** (Kafka's `onPartitionsRevoked`, `onPartitionsAssigned`) let you flush state and drain in-flight work *before* the pause deepens.
- Connects to: consumer group lag monitoring, idempotent processing, exactly-once semantics, and backpressure handling in streaming pipelines.
- Revisit: offset storage backends (Kafka-internal vs. external), scaling strategies (scaling *down* is often more disruptive than scaling up), and how different assignment strategies affect data locality.
