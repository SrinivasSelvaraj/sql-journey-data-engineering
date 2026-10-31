---
date: 2026-10-31
phase: streaming
topic: Kafka partitioning and ordering guarantees
---

# Kafka partitioning and ordering guarantees

*Streaming and distributed processing*

## Concept

Kafka partitioning assigns messages to partitions based on a key, and within a single partition, Kafka guarantees strict ordering—messages are written and read sequentially. However, ordering guarantees only hold *within* a partition; messages across different partitions have no guaranteed order. This becomes critical in streaming pipelines where you need to preserve temporal or causal relationships: if job postings for the same company arrive out of sequence across partitions, downstream aggregations (like "most recent salary for company X") become unreliable. Without explicit partitioning strategy, a system might process a job update before the original posting, causing data inconsistency.

The key decision is choosing a partition key. If you partition by `job_id`, all updates to a single job stay ordered; if you partition by `job_location`, you lose ordering across jobs within that location. Unkeyed messages (null key) round-robin across partitions, destroying ordering entirely. In practice, breaking ordering guarantees often goes unnoticed until you hit edge cases—reprocessing, replays, or failovers—where you discover your aggregations depend on arrival order and silently produced wrong results.

## Practice

**Problem:** A data pipeline ingests job postings and updates (salary corrections, location changes) to Kafka. You need to ensure that for each `job_id`, events are processed in the order they occurred, so that final job records reflect the correct state. However, the pipeline currently uses null keys, causing events to scatter across partitions randomly.

```sql
-- Kafka producer configuration (pseudocode):
-- Key: job_id (ensures all events for same job go to same partition)
-- Topic: job_postings_stream
-- Partition assignment: hash(job_id) % num_partitions

-- Consumer logic to reconstruct correct job state:
WITH ordered_events AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    kafka_timestamp,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY kafka_timestamp ASC) AS event_seq
  FROM job_postings_stream
)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM ordered_events
WHERE event_seq = ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY kafka_timestamp DESC)
  -- Keep only the latest event per job_id
```

## Notes

- **Partition key selection is permanent strategy, not tuning:** Changing keys mid-pipeline requires re-ingestion. Choose based on your primary access pattern (by job? by company? by location?), not just even distribution.
- **"In-order" is local, not global:** Kafka guarantees order within partition + consumer group, but if you have multiple consumer instances, they read different partitions in parallel; you must re-order downstream (use timestamps, sequence numbers, or state stores).
- **Null keys cause silent data loss of ordering:** Easy to miss in development; test with out-of-sequence message injection to catch bugs before production.
- **Related: consumer group rebalancing, offset management, and idempotent processing**—even with correct partitioning, a rebalance mid-processing can cause duplicates or skipped messages unless you handle offsets carefully.
- **Revisit when scaling:** Adding partitions does not re-partition existing data; new producers use new partition count, but old messages stay in old partitions. Plan partition count upfront.
