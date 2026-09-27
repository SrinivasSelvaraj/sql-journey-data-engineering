---
date: 2026-09-27
phase: streaming
topic: Watermark alignment across parallel tasks
---

# Watermark alignment across parallel tasks

*Streaming and distributed processing*

## Concept

Watermark alignment across parallel tasks ensures all parallel subtasks in a distributed streaming pipeline agree on how far the computation has progressed through event time, preventing data loss and duplicate results. Without alignment, one subtask may be 10 minutes ahead in processing time while another lags, causing late-arriving records to be dropped prematurely by the faster subtask or processed redundantly by slower ones when they eventually catch up.

In streaming systems like Flink, Spark Streaming, or Kafka Streams, watermarks represent the threshold beyond which no earlier data is expected to arrive. When a single operator has multiple parallel instances (e.g., 4 Kafka partitions consumed in parallel), each subtask maintains its own watermark. The global watermark—used for triggering windows and deciding when results are final—must be the *minimum* across all subtasks, not the maximum. If subtask 1 is at 14:00 and subtask 2 is at 13:50, the global watermark is 13:50; otherwise, data at 13:55 from subtask 2 gets discarded.

Misalignment causes two problems: (1) **premature result emission** when a fast subtask advances its watermark without waiting for slower partitions, dropping valid late data; (2) **duplicate or inconsistent state** when watermark coordination fails during recovery or rebalancing. This is especially critical for deduplication, sessionization, and exactly-once semantics.

## Practice

**Problem:** You're aggregating job postings by location to count new postings per hour. The data comes from three Kafka partitions in parallel. Partition 0 (US East) is fast; Partition 1 (US West) is slow due to network lag; Partition 2 (EU) is moderate. Without watermark alignment, the hourly count for 14:00–15:00 fires at 14:59 from Partition 0, but Partition 1 still has records from 14:30 that haven't been processed. You need to ensure all three partitions' watermarks are synchronized before emitting results.

```sql
-- Flink SQL / Kafka Source with watermark alignment
CREATE TABLE job_postings_raw (
  job_id BIGINT,
  job_title_short STRING,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date TIMESTAMP(3),
  job_location STRING,
  WATERMARK FOR job_posted_date AS job_posted_date - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'job_postings',
  'properties.bootstrap.servers' = 'localhost:9092',
  'properties.group.id' = 'job_agg',
  -- Force alignment: all partitions blocked until slowest reaches watermark
  'scan.startup.mode' = 'earliest',
  'properties.fetch.min.bytes' = '10000'  -- batch to reduce partition skew
);

-- Aggregate with window: watermark alignment ensures all data in [14:00, 15:00) is received
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) as hour_start,
  job_location,
  COUNT(*) as posting_count
FROM job_postings_raw
GROUP BY
  TUMBLE(job_posted_date, INTERVAL '1' HOUR),
  job_location;
```

The WATERMARK clause delays any subtask's local watermark advancement until it matches the slowest partition, preventing premature window closure.

## Notes

- **Min, not max:** The global watermark is always the *minimum* of all subtask watermarks. Forgetting this causes fast tasks to emit results before slow tasks have finished their input.
- **Idle sources:** If one partition stops receiving data, its watermark stalls, blocking the entire pipeline. Use idle timeout detection (`allowedLateness` or `idleStateTimeout`) to advance watermarks past idle partitions.
- **Backpressure vs. alignment:** Watermark alignment can cause stalled subtasks (backpressure) if one partition is much slower. Monitor lag metrics (`currentLowWatermark`) to detect bottlenecks.
- **Shuffle and rebalancing:** Watermark alignment is per-operator. After a shuffle (repartition), watermarks reset; each new set of parallel subtasks must re-align. Understand how your framework handles alignment across operator boundaries.
- **Test with skew:** Simulate partition lag during testing by injecting delays in upstream sources; verify that late data still arrives and is processed, not silently dropped.
